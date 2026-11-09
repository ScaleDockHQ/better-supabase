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
    WHEN 'message'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.messages s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.read'::text) AS tenant_ids_with)))
    WHEN 'conversation'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.conversations s
      WHERE ((s.id = (s.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.read'::text) AS tenant_ids_with)))
    WHEN 'channel'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.channels s
      WHERE ((s.id = (s.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.read'::text) AS tenant_ids_with)))
    WHEN 'company'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.companies s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contacts.read'::text) AS tenant_ids_with)))
    WHEN 'person'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.people s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contacts.read'::text) AS tenant_ids_with)))
    WHEN 'deal'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.deals s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('deals.read'::text) AS tenant_ids_with)))
    WHEN 'course'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.courses s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('courses.read'::text) AS tenant_ids_with)))
    WHEN 'post'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.posts s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('posts.read'::text) AS tenant_ids_with)))
    WHEN 'activity'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.activities s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('activities.read'::text) AS tenant_ids_with)))
    WHEN 'quote'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.quotes s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('quotes.read'::text) AS tenant_ids_with)))
    WHEN 'work_item'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.work_items s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('tasks.read'::text) AS tenant_ids_with)))
    WHEN 'employee'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.employees s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('employees.read'::text) AS tenant_ids_with)))
    WHEN 'invoice'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.invoices s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('invoices.read'::text) AS tenant_ids_with)))
    WHEN 'ledger_account'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.ledger_accounts s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('ledger.read'::text) AS tenant_ids_with)))
    WHEN 'product'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.products s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'product_variant'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.product_variants s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'rfq'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.rfqs s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('rfqs.read'::text) AS tenant_ids_with)))
    WHEN 'till'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.tills s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('tills.read'::text) AS tenant_ids_with)))
    WHEN 'order'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.orders s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('orders.read'::text) AS tenant_ids_with)))
    WHEN 'calendar_event'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.calendar_events s
      WHERE ((s.id = (s.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('calendar.read'::text) AS tenant_ids_with)))
    WHEN 'booking'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.bookings s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('bookings.read'::text) AS tenant_ids_with)))
    WHEN 'asset'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.assets s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('assets.read'::text) AS tenant_ids_with)))
    WHEN 'asset_location'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.asset_locations s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('assets.read'::text) AS tenant_ids_with)))
    WHEN 'lease'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.leases s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('leases.read'::text) AS tenant_ids_with)))
    WHEN 'expense_report'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.expense_reports s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('expenses.read'::text) AS tenant_ids_with)))
    WHEN 'expense_line'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.expense_lines s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('expenses.read'::text) AS tenant_ids_with)))
    WHEN 'donation_fund'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.donation_funds s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('donations.read'::text) AS tenant_ids_with)))
    WHEN 'work_order'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.work_orders s
      WHERE ((s.id = (s.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('dispatch.read'::text) AS tenant_ids_with)))
    WHEN 'shipment'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.shipments s
      WHERE ((s.id = (s.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('shipments.read'::text) AS tenant_ids_with)))
    WHEN 'contract'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.contracts s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contracts.read'::text) AS tenant_ids_with)))
    WHEN 'control'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.controls s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('compliance.read'::text) AS tenant_ids_with)))
    WHEN 'compliance_policy'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.compliance_policies s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('compliance.read'::text) AS tenant_ids_with)))
    WHEN 'qualification_type'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.qualification_types s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('qualifications.read'::text) AS tenant_ids_with)))
    WHEN 'risk'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.risks s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('risks.read'::text) AS tenant_ids_with)))
    WHEN 'case'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.cases s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('cases.read'::text) AS tenant_ids_with)))
    WHEN 'inspection'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.inspections s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('inspections.read'::text) AS tenant_ids_with)))
    WHEN 'inspection_program'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.inspection_programs s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('inspections.read'::text) AS tenant_ids_with)))
    WHEN 'inspection_finding'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.inspection_findings s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('inspections.read'::text) AS tenant_ids_with)))
    WHEN 'form'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.forms s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('forms.read'::text) AS tenant_ids_with)))
    WHEN 'meeting'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.meetings s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('meetings.read'::text) AS tenant_ids_with)))
    WHEN 'meeting_decision'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.meeting_decisions s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('meetings.read'::text) AS tenant_ids_with)))
    WHEN 'maintenance_plan'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.maintenance_plans s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('maintenance.read'::text) AS tenant_ids_with)))
    WHEN 'dam_usage_right'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.dam_usage_rights s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('dam.read'::text) AS tenant_ids_with)))
    WHEN 'lims_sample'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.lims_samples s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('lims.read'::text) AS tenant_ids_with)))
    WHEN 'tax_code'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.tax_codes s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('tax.read'::text) AS tenant_ids_with)))
    WHEN 'production_order'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.production_orders s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('manufacturing.read'::text) AS tenant_ids_with)))
    WHEN 'work_center'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.work_centers s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('manufacturing.read'::text) AS tenant_ids_with)))
    WHEN 'bank_account'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.bank_accounts s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('banking.read'::text) AS tenant_ids_with)))
    WHEN 'care_plan'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.care_plans s
      WHERE ((s.id = (s.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('care_plans.read'::text) AS tenant_ids_with)))
    WHEN 'incident'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.incidents s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('incidents.read'::text) AS tenant_ids_with)))
    WHEN 'content_entry'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.content_entries s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('content.read'::text) AS tenant_ids_with)))
    WHEN 'document'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.documents s
      WHERE ((s.id = (s.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('documents.read'::text) AS tenant_ids_with)))
    WHEN 'customer'::text THEN ((EXISTS ( SELECT 1
       FROM public.customers s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.organization_id = attachments.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('customers.read'::text) AS tenant_ids_with)))
    WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.drive_nodes s
      WHERE
        ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id) AND ((s.tenant_id IN ( SELECT better_supabase.tenant_ids_with('drive.read'::text) AS
        tenant_ids_with)) AND COALESCE(better_supabase.drive_node_readable(s.id), false)))))
    WHEN 'application'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.applications s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('hiring.read'::text) AS tenant_ids_with)))
    WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
       FROM public.change_requests s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.organization_id = attachments.tenant_id))))
    WHEN 'project'::text THEN (EXISTS ( SELECT 1
       FROM public.projects s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.organization_id = attachments.tenant_id))))
    WHEN 'task'::text THEN (EXISTS ( SELECT 1
       FROM public.tasks s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.organization_id = attachments.tenant_id))))
    ELSE false
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
    WHEN 'message'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.messages s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.read'::text) AS tenant_ids_with)))
    WHEN 'conversation'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.conversations s
      WHERE ((s.id = (s.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.read'::text) AS tenant_ids_with)))
    WHEN 'channel'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.channels s
      WHERE ((s.id = (s.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.read'::text) AS tenant_ids_with)))
    WHEN 'company'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.companies s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contacts.read'::text) AS tenant_ids_with)))
    WHEN 'person'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.people s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contacts.read'::text) AS tenant_ids_with)))
    WHEN 'deal'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.deals s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('deals.read'::text) AS tenant_ids_with)))
    WHEN 'course'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.courses s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('courses.read'::text) AS tenant_ids_with)))
    WHEN 'post'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.posts s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('posts.read'::text) AS tenant_ids_with)))
    WHEN 'activity'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.activities s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('activities.read'::text) AS tenant_ids_with)))
    WHEN 'quote'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.quotes s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('quotes.read'::text) AS tenant_ids_with)))
    WHEN 'work_item'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.work_items s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('tasks.read'::text) AS tenant_ids_with)))
    WHEN 'employee'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.employees s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('employees.read'::text) AS tenant_ids_with)))
    WHEN 'invoice'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.invoices s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('invoices.read'::text) AS tenant_ids_with)))
    WHEN 'ledger_account'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.ledger_accounts s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('ledger.read'::text) AS tenant_ids_with)))
    WHEN 'product'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.products s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'product_variant'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.product_variants s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'rfq'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.rfqs s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('rfqs.read'::text) AS tenant_ids_with)))
    WHEN 'till'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.tills s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('tills.read'::text) AS tenant_ids_with)))
    WHEN 'order'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.orders s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('orders.read'::text) AS tenant_ids_with)))
    WHEN 'calendar_event'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.calendar_events s
      WHERE ((s.id = (s.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('calendar.read'::text) AS tenant_ids_with)))
    WHEN 'booking'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.bookings s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('bookings.read'::text) AS tenant_ids_with)))
    WHEN 'asset'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.assets s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('assets.read'::text) AS tenant_ids_with)))
    WHEN 'asset_location'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.asset_locations s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('assets.read'::text) AS tenant_ids_with)))
    WHEN 'lease'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.leases s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('leases.read'::text) AS tenant_ids_with)))
    WHEN 'expense_report'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.expense_reports s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('expenses.read'::text) AS tenant_ids_with)))
    WHEN 'expense_line'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.expense_lines s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('expenses.read'::text) AS tenant_ids_with)))
    WHEN 'donation_fund'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.donation_funds s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('donations.read'::text) AS tenant_ids_with)))
    WHEN 'work_order'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.work_orders s
      WHERE ((s.id = (s.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('dispatch.read'::text) AS tenant_ids_with)))
    WHEN 'shipment'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.shipments s
      WHERE ((s.id = (s.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('shipments.read'::text) AS tenant_ids_with)))
    WHEN 'contract'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.contracts s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contracts.read'::text) AS tenant_ids_with)))
    WHEN 'control'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.controls s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('compliance.read'::text) AS tenant_ids_with)))
    WHEN 'compliance_policy'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.compliance_policies s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('compliance.read'::text) AS tenant_ids_with)))
    WHEN 'qualification_type'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.qualification_types s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('qualifications.read'::text) AS tenant_ids_with)))
    WHEN 'risk'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.risks s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('risks.read'::text) AS tenant_ids_with)))
    WHEN 'case'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.cases s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('cases.read'::text) AS tenant_ids_with)))
    WHEN 'inspection'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.inspections s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('inspections.read'::text) AS tenant_ids_with)))
    WHEN 'inspection_program'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.inspection_programs s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('inspections.read'::text) AS tenant_ids_with)))
    WHEN 'inspection_finding'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.inspection_findings s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('inspections.read'::text) AS tenant_ids_with)))
    WHEN 'form'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.forms s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('forms.read'::text) AS tenant_ids_with)))
    WHEN 'meeting'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.meetings s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('meetings.read'::text) AS tenant_ids_with)))
    WHEN 'meeting_decision'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.meeting_decisions s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('meetings.read'::text) AS tenant_ids_with)))
    WHEN 'maintenance_plan'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.maintenance_plans s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('maintenance.read'::text) AS tenant_ids_with)))
    WHEN 'dam_usage_right'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.dam_usage_rights s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('dam.read'::text) AS tenant_ids_with)))
    WHEN 'lims_sample'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.lims_samples s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('lims.read'::text) AS tenant_ids_with)))
    WHEN 'tax_code'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.tax_codes s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('tax.read'::text) AS tenant_ids_with)))
    WHEN 'production_order'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.production_orders s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('manufacturing.read'::text) AS tenant_ids_with)))
    WHEN 'work_center'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.work_centers s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('manufacturing.read'::text) AS tenant_ids_with)))
    WHEN 'bank_account'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.bank_accounts s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('banking.read'::text) AS tenant_ids_with)))
    WHEN 'care_plan'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.care_plans s
      WHERE ((s.id = (s.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('care_plans.read'::text) AS tenant_ids_with)))
    WHEN 'incident'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.incidents s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('incidents.read'::text) AS tenant_ids_with)))
    WHEN 'content_entry'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.content_entries s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('content.read'::text) AS tenant_ids_with)))
    WHEN 'document'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.documents s
      WHERE ((s.id = (s.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('documents.read'::text) AS tenant_ids_with)))
    WHEN 'customer'::text THEN ((EXISTS ( SELECT 1
       FROM public.customers s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.organization_id = attachments.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('customers.read'::text) AS tenant_ids_with)))
    WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.drive_nodes s
      WHERE
        ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id) AND ((s.tenant_id IN ( SELECT better_supabase.tenant_ids_with('drive.read'::text) AS
        tenant_ids_with)) AND COALESCE(better_supabase.drive_node_readable(s.id), false)))))
    WHEN 'application'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.applications s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('hiring.read'::text) AS tenant_ids_with)))
    WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
       FROM public.change_requests s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.organization_id = attachments.tenant_id))))
    WHEN 'project'::text THEN (EXISTS ( SELECT 1
       FROM public.projects s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.organization_id = attachments.tenant_id))))
    WHEN 'task'::text THEN (EXISTS ( SELECT 1
       FROM public.tasks s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.organization_id = attachments.tenant_id))))
    ELSE false
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
    WHEN 'message'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.messages s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.read'::text) AS tenant_ids_with)))
    WHEN 'conversation'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.conversations s
      WHERE ((s.id = (s.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.read'::text) AS tenant_ids_with)))
    WHEN 'channel'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.channels s
      WHERE ((s.id = (s.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.read'::text) AS tenant_ids_with)))
    WHEN 'company'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.companies s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contacts.read'::text) AS tenant_ids_with)))
    WHEN 'person'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.people s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contacts.read'::text) AS tenant_ids_with)))
    WHEN 'deal'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.deals s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('deals.read'::text) AS tenant_ids_with)))
    WHEN 'course'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.courses s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('courses.read'::text) AS tenant_ids_with)))
    WHEN 'post'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.posts s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('posts.read'::text) AS tenant_ids_with)))
    WHEN 'activity'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.activities s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('activities.read'::text) AS tenant_ids_with)))
    WHEN 'quote'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.quotes s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('quotes.read'::text) AS tenant_ids_with)))
    WHEN 'work_item'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.work_items s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('tasks.read'::text) AS tenant_ids_with)))
    WHEN 'employee'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.employees s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('employees.read'::text) AS tenant_ids_with)))
    WHEN 'invoice'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.invoices s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('invoices.read'::text) AS tenant_ids_with)))
    WHEN 'ledger_account'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.ledger_accounts s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('ledger.read'::text) AS tenant_ids_with)))
    WHEN 'product'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.products s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'product_variant'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.product_variants s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'rfq'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.rfqs s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('rfqs.read'::text) AS tenant_ids_with)))
    WHEN 'till'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.tills s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('tills.read'::text) AS tenant_ids_with)))
    WHEN 'order'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.orders s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('orders.read'::text) AS tenant_ids_with)))
    WHEN 'calendar_event'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.calendar_events s
      WHERE ((s.id = (s.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('calendar.read'::text) AS tenant_ids_with)))
    WHEN 'booking'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.bookings s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('bookings.read'::text) AS tenant_ids_with)))
    WHEN 'asset'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.assets s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('assets.read'::text) AS tenant_ids_with)))
    WHEN 'asset_location'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.asset_locations s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('assets.read'::text) AS tenant_ids_with)))
    WHEN 'lease'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.leases s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('leases.read'::text) AS tenant_ids_with)))
    WHEN 'expense_report'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.expense_reports s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('expenses.read'::text) AS tenant_ids_with)))
    WHEN 'expense_line'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.expense_lines s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('expenses.read'::text) AS tenant_ids_with)))
    WHEN 'donation_fund'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.donation_funds s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('donations.read'::text) AS tenant_ids_with)))
    WHEN 'work_order'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.work_orders s
      WHERE ((s.id = (s.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('dispatch.read'::text) AS tenant_ids_with)))
    WHEN 'shipment'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.shipments s
      WHERE ((s.id = (s.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('shipments.read'::text) AS tenant_ids_with)))
    WHEN 'contract'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.contracts s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contracts.read'::text) AS tenant_ids_with)))
    WHEN 'control'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.controls s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('compliance.read'::text) AS tenant_ids_with)))
    WHEN 'compliance_policy'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.compliance_policies s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('compliance.read'::text) AS tenant_ids_with)))
    WHEN 'qualification_type'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.qualification_types s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('qualifications.read'::text) AS tenant_ids_with)))
    WHEN 'risk'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.risks s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('risks.read'::text) AS tenant_ids_with)))
    WHEN 'case'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.cases s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('cases.read'::text) AS tenant_ids_with)))
    WHEN 'inspection'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.inspections s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('inspections.read'::text) AS tenant_ids_with)))
    WHEN 'inspection_program'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.inspection_programs s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('inspections.read'::text) AS tenant_ids_with)))
    WHEN 'inspection_finding'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.inspection_findings s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('inspections.read'::text) AS tenant_ids_with)))
    WHEN 'form'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.forms s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('forms.read'::text) AS tenant_ids_with)))
    WHEN 'meeting'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.meetings s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('meetings.read'::text) AS tenant_ids_with)))
    WHEN 'meeting_decision'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.meeting_decisions s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('meetings.read'::text) AS tenant_ids_with)))
    WHEN 'maintenance_plan'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.maintenance_plans s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('maintenance.read'::text) AS tenant_ids_with)))
    WHEN 'dam_usage_right'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.dam_usage_rights s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('dam.read'::text) AS tenant_ids_with)))
    WHEN 'lims_sample'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.lims_samples s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('lims.read'::text) AS tenant_ids_with)))
    WHEN 'tax_code'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.tax_codes s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('tax.read'::text) AS tenant_ids_with)))
    WHEN 'production_order'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.production_orders s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('manufacturing.read'::text) AS tenant_ids_with)))
    WHEN 'work_center'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.work_centers s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('manufacturing.read'::text) AS tenant_ids_with)))
    WHEN 'bank_account'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.bank_accounts s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('banking.read'::text) AS tenant_ids_with)))
    WHEN 'care_plan'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.care_plans s
      WHERE ((s.id = (s.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('care_plans.read'::text) AS tenant_ids_with)))
    WHEN 'incident'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.incidents s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('incidents.read'::text) AS tenant_ids_with)))
    WHEN 'content_entry'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.content_entries s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('content.read'::text) AS tenant_ids_with)))
    WHEN 'document'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.documents s
      WHERE ((s.id = (s.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('documents.read'::text) AS tenant_ids_with)))
    WHEN 'customer'::text THEN ((EXISTS ( SELECT 1
       FROM public.customers s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.organization_id = attachments.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('customers.read'::text) AS tenant_ids_with)))
    WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.drive_nodes s
      WHERE
        ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id) AND ((s.tenant_id IN ( SELECT better_supabase.tenant_ids_with('drive.read'::text) AS
        tenant_ids_with)) AND COALESCE(better_supabase.drive_node_readable(s.id), false)))))
    WHEN 'application'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.applications s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('hiring.read'::text) AS tenant_ids_with)))
    WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
       FROM public.change_requests s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.organization_id = attachments.tenant_id))))
    WHEN 'project'::text THEN (EXISTS ( SELECT 1
       FROM public.projects s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.organization_id = attachments.tenant_id))))
    WHEN 'task'::text THEN (EXISTS ( SELECT 1
       FROM public.tasks s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.organization_id = attachments.tenant_id))))
    ELSE false
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
    WHEN 'message'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.messages s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.read'::text) AS tenant_ids_with)))
    WHEN 'conversation'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.conversations s
      WHERE ((s.id = (s.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.read'::text) AS tenant_ids_with)))
    WHEN 'channel'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.channels s
      WHERE ((s.id = (s.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.read'::text) AS tenant_ids_with)))
    WHEN 'company'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.companies s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contacts.read'::text) AS tenant_ids_with)))
    WHEN 'person'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.people s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contacts.read'::text) AS tenant_ids_with)))
    WHEN 'deal'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.deals s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('deals.read'::text) AS tenant_ids_with)))
    WHEN 'course'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.courses s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('courses.read'::text) AS tenant_ids_with)))
    WHEN 'post'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.posts s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('posts.read'::text) AS tenant_ids_with)))
    WHEN 'activity'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.activities s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('activities.read'::text) AS tenant_ids_with)))
    WHEN 'quote'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.quotes s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('quotes.read'::text) AS tenant_ids_with)))
    WHEN 'work_item'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.work_items s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('tasks.read'::text) AS tenant_ids_with)))
    WHEN 'employee'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.employees s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('employees.read'::text) AS tenant_ids_with)))
    WHEN 'invoice'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.invoices s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('invoices.read'::text) AS tenant_ids_with)))
    WHEN 'ledger_account'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.ledger_accounts s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('ledger.read'::text) AS tenant_ids_with)))
    WHEN 'product'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.products s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'product_variant'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.product_variants s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'rfq'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.rfqs s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('rfqs.read'::text) AS tenant_ids_with)))
    WHEN 'till'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.tills s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('tills.read'::text) AS tenant_ids_with)))
    WHEN 'order'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.orders s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('orders.read'::text) AS tenant_ids_with)))
    WHEN 'calendar_event'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.calendar_events s
      WHERE ((s.id = (s.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('calendar.read'::text) AS tenant_ids_with)))
    WHEN 'booking'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.bookings s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('bookings.read'::text) AS tenant_ids_with)))
    WHEN 'asset'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.assets s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('assets.read'::text) AS tenant_ids_with)))
    WHEN 'asset_location'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.asset_locations s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('assets.read'::text) AS tenant_ids_with)))
    WHEN 'lease'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.leases s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('leases.read'::text) AS tenant_ids_with)))
    WHEN 'expense_report'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.expense_reports s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('expenses.read'::text) AS tenant_ids_with)))
    WHEN 'expense_line'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.expense_lines s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('expenses.read'::text) AS tenant_ids_with)))
    WHEN 'donation_fund'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.donation_funds s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('donations.read'::text) AS tenant_ids_with)))
    WHEN 'work_order'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.work_orders s
      WHERE ((s.id = (s.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('dispatch.read'::text) AS tenant_ids_with)))
    WHEN 'shipment'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.shipments s
      WHERE ((s.id = (s.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('shipments.read'::text) AS tenant_ids_with)))
    WHEN 'contract'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.contracts s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contracts.read'::text) AS tenant_ids_with)))
    WHEN 'control'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.controls s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('compliance.read'::text) AS tenant_ids_with)))
    WHEN 'compliance_policy'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.compliance_policies s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('compliance.read'::text) AS tenant_ids_with)))
    WHEN 'qualification_type'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.qualification_types s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('qualifications.read'::text) AS tenant_ids_with)))
    WHEN 'risk'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.risks s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('risks.read'::text) AS tenant_ids_with)))
    WHEN 'case'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.cases s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('cases.read'::text) AS tenant_ids_with)))
    WHEN 'inspection'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.inspections s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('inspections.read'::text) AS tenant_ids_with)))
    WHEN 'inspection_program'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.inspection_programs s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('inspections.read'::text) AS tenant_ids_with)))
    WHEN 'inspection_finding'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.inspection_findings s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('inspections.read'::text) AS tenant_ids_with)))
    WHEN 'form'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.forms s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('forms.read'::text) AS tenant_ids_with)))
    WHEN 'meeting'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.meetings s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('meetings.read'::text) AS tenant_ids_with)))
    WHEN 'meeting_decision'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.meeting_decisions s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('meetings.read'::text) AS tenant_ids_with)))
    WHEN 'maintenance_plan'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.maintenance_plans s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('maintenance.read'::text) AS tenant_ids_with)))
    WHEN 'dam_usage_right'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.dam_usage_rights s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('dam.read'::text) AS tenant_ids_with)))
    WHEN 'lims_sample'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.lims_samples s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('lims.read'::text) AS tenant_ids_with)))
    WHEN 'tax_code'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.tax_codes s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('tax.read'::text) AS tenant_ids_with)))
    WHEN 'production_order'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.production_orders s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('manufacturing.read'::text) AS tenant_ids_with)))
    WHEN 'work_center'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.work_centers s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('manufacturing.read'::text) AS tenant_ids_with)))
    WHEN 'bank_account'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.bank_accounts s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('banking.read'::text) AS tenant_ids_with)))
    WHEN 'care_plan'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.care_plans s
      WHERE ((s.id = (s.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('care_plans.read'::text) AS tenant_ids_with)))
    WHEN 'incident'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.incidents s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('incidents.read'::text) AS tenant_ids_with)))
    WHEN 'content_entry'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.content_entries s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('content.read'::text) AS tenant_ids_with)))
    WHEN 'document'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.documents s
      WHERE ((s.id = (s.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('documents.read'::text) AS tenant_ids_with)))
    WHEN 'customer'::text THEN ((EXISTS ( SELECT 1
       FROM public.customers s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.organization_id = attachments.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('customers.read'::text) AS tenant_ids_with)))
    WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.drive_nodes s
      WHERE
        ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id) AND ((s.tenant_id IN ( SELECT better_supabase.tenant_ids_with('drive.read'::text) AS
        tenant_ids_with)) AND COALESCE(better_supabase.drive_node_readable(s.id), false)))))
    WHEN 'application'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.applications s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.tenant_id = s.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('hiring.read'::text) AS tenant_ids_with)))
    WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
       FROM public.change_requests s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.organization_id = attachments.tenant_id))))
    WHEN 'project'::text THEN (EXISTS ( SELECT 1
       FROM public.projects s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.organization_id = attachments.tenant_id))))
    WHEN 'task'::text THEN (EXISTS ( SELECT 1
       FROM public.tasks s
      WHERE ((s.id = (attachments.subject_id)::uuid) AND (s.organization_id = attachments.tenant_id))))
    ELSE false
END)))));
