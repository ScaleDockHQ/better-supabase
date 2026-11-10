SET local check_function_bodies = off;

DROP POLICY "bsb_consents_read" ON "better_supabase"."consents";

DROP POLICY "bsb_tenant_scope_select" ON "better_supabase"."consents";

DROP POLICY "bsb_field_changes_read" ON "better_supabase"."field_changes";

DROP POLICY "bsb_tenant_scope_select" ON "better_supabase"."field_changes";

DROP POLICY "bsb_funding_awards_read" ON "better_supabase"."funding_awards";

DROP POLICY "bsb_tenant_scope_select" ON "better_supabase"."funding_awards";

DROP POLICY "bsb_medication_orders_read" ON "better_supabase"."medication_orders";

DROP POLICY "bsb_tenant_scope_select" ON "better_supabase"."medication_orders";

DROP POLICY "bsb_observations_read" ON "better_supabase"."observations";

DROP POLICY "bsb_tenant_scope_select" ON "better_supabase"."observations";

DROP POLICY "bsb_pipeline_stage_history_read" ON "better_supabase"."pipeline_stage_history";

DROP POLICY "bsb_tenant_scope_select" ON "better_supabase"."pipeline_stage_history";

DROP POLICY "bsb_sla_clocks_read" ON "better_supabase"."sla_clocks";

DROP POLICY "bsb_tenant_scope_select" ON "better_supabase"."sla_clocks";

CREATE OR REPLACE FUNCTION api.get_company (
  id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_company"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_person (
  id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_person"($1) $function$;

CREATE OR REPLACE FUNCTION better_supabase.get_company (
  id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select to_jsonb(x) || jsonb_build_object('roles', x."roles", 'customer_terms_id', x."customer_terms_id", 'supplier_terms_id', x."supplier_terms_id", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'credit_block', x."credit_block", 'supplier_status', x."supplier_status", 'language', x."language") from "better_supabase"."companies" x
  where x."id" = get_company.id and x."archived_at" is null
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_person (
  id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select to_jsonb(x) || jsonb_build_object('roles', x."roles", 'customer_terms_id', x."customer_terms_id", 'supplier_terms_id', x."supplier_terms_id", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'credit_block', x."credit_block", 'supplier_status', x."supplier_status", 'language', x."language") from "better_supabase"."people" x
  where x."id" = get_person.id and x."archived_at" is null
$function$;

CREATE OR REPLACE FUNCTION better_supabase.search_enqueue (
  subject_type text,
  subject_id   text
)
  RETURNS void
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_key text := search_enqueue.subject_type || E'\x1f' || search_enqueue.subject_id;
  v_name text := 'better_supabase.search_dirty_' || (hashtext(v_key) & 255)::text;
  v_dirty text;
begin
  if coalesce(current_setting('better_supabase.search_deferred', true), '') = 'on' then
    v_dirty := coalesce(current_setting(v_name, true), '');
    if position(E'\n' || v_key || E'\n' in E'\n' || v_dirty) = 0 then
      perform set_config(v_name, v_dirty || v_key || E'\n', true);
    end if;
  else
    perform "better_supabase"."search_refresh"(search_enqueue.subject_type, search_enqueue.subject_id);
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.search_refresh_dirty()
  RETURNS integer
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_count integer := 0;
  v_bucket integer;
  v_name text;
  v_dirty text;
  v_line text;
begin
  for v_bucket in 0..255 loop
    v_name := 'better_supabase.search_dirty_' || v_bucket::text;
    v_dirty := coalesce(current_setting(v_name, true), '');
    if v_dirty <> '' then
      perform set_config(v_name, '', true);
      for v_line in select l from string_to_table(v_dirty, E'\n') l where l <> '' loop
        if "better_supabase"."search_refresh"(split_part(v_line, E'\x1f', 1), split_part(v_line, E'\x1f', 2)) then
          v_count := v_count + 1;
        end if;
      end loop;
    end if;
  end loop;
  return v_count;
end;
$function$;

CREATE POLICY "bsb_consents_read" ON "better_supabase"."consents"
  FOR SELECT
  TO "authenticated"
  USING ((((tenant_id IN ( SELECT better_supabase.tenant_ids_with('consents.read'::text) AS tenant_ids_with)) AND
CASE subject_type
    WHEN 'message'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.messages s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.read'::text) AS tenant_ids_with)))
    WHEN 'conversation'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.conversations s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.read'::text) AS tenant_ids_with)))
    WHEN 'channel'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.channels s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.read'::text) AS tenant_ids_with)))
    WHEN 'company'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.companies s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contacts.read'::text) AS tenant_ids_with)))
    WHEN 'person'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.people s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contacts.read'::text) AS tenant_ids_with)))
    WHEN 'deal'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.deals s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('deals.read'::text) AS tenant_ids_with)))
    WHEN 'course'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.courses s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('courses.read'::text) AS tenant_ids_with)))
    WHEN 'post'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.posts s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('posts.read'::text) AS tenant_ids_with)))
    WHEN 'activity'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.activities s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('activities.read'::text) AS tenant_ids_with)))
    WHEN 'quote'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.quotes s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('quotes.read'::text) AS tenant_ids_with)))
    WHEN 'work_item'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.work_items s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('tasks.read'::text) AS tenant_ids_with)))
    WHEN 'employee'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.employees s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('employees.read'::text) AS tenant_ids_with)))
    WHEN 'invoice'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.invoices s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('invoices.read'::text) AS tenant_ids_with)))
    WHEN 'ledger_account'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.ledger_accounts s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('ledger.read'::text) AS tenant_ids_with)))
    WHEN 'product'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.products s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'product_variant'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.product_variants s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'order'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.orders s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('orders.read'::text) AS tenant_ids_with)))
    WHEN 'calendar_event'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.calendar_events s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('calendar.read'::text) AS tenant_ids_with)))
    WHEN 'booking'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.bookings s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('bookings.read'::text) AS tenant_ids_with)))
    WHEN 'asset'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.assets s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('assets.read'::text) AS tenant_ids_with)))
    WHEN 'asset_location'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.asset_locations s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('assets.read'::text) AS tenant_ids_with)))
    WHEN 'lease'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.leases s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('leases.read'::text) AS tenant_ids_with)))
    WHEN 'expense_report'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.expense_reports s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('expenses.read'::text) AS tenant_ids_with)))
    WHEN 'expense_line'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.expense_lines s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('expenses.read'::text) AS tenant_ids_with)))
    WHEN 'donation_fund'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.donation_funds s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('donations.read'::text) AS tenant_ids_with)))
    WHEN 'work_order'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.work_orders s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('dispatch.read'::text) AS tenant_ids_with)))
    WHEN 'shipment'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.shipments s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('shipments.read'::text) AS tenant_ids_with)))
    WHEN 'contract'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.contracts s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contracts.read'::text) AS tenant_ids_with)))
    WHEN 'control'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.controls s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('compliance.read'::text) AS tenant_ids_with)))
    WHEN 'compliance_policy'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.compliance_policies s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('compliance.read'::text) AS tenant_ids_with)))
    WHEN 'qualification_type'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.qualification_types s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('qualifications.read'::text) AS tenant_ids_with)))
    WHEN 'risk'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.risks s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('risks.read'::text) AS tenant_ids_with)))
    WHEN 'case'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.cases s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('cases.read'::text) AS tenant_ids_with)))
    WHEN 'form'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.forms s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('forms.read'::text) AS tenant_ids_with)))
    WHEN 'tax_code'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.tax_codes s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('tax.read'::text) AS tenant_ids_with)))
    WHEN 'incident'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.incidents s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('incidents.read'::text) AS tenant_ids_with)))
    WHEN 'content_entry'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.content_entries s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('content.read'::text) AS tenant_ids_with)))
    WHEN 'document'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.documents s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('documents.read'::text) AS tenant_ids_with)))
    WHEN 'customer'::text THEN ((EXISTS ( SELECT 1
       FROM public.customers s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.organization_id = consents.tenant_id)))) AND
        ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('customers.read'::text) AS tenant_ids_with)) OR better_supabase.is_subject_member('customer'::text, subject_id)))
    WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.drive_nodes s
      WHERE
        ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id) AND (((consents.tenant_id IN ( SELECT better_supabase.tenant_ids_with('drive.read'::text) AS
        tenant_ids_with)) AND COALESCE(better_supabase.drive_node_readable(s.id), false)) OR better_supabase.is_subject_member('drive_node'::text, consents.subject_id)))))
    WHEN 'organization'::text THEN (EXISTS ( SELECT 1
       FROM public.organizations s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.id = consents.tenant_id))))
    WHEN 'application'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.applications s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('hiring.read'::text) AS tenant_ids_with)))
    WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
       FROM public.change_requests s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.organization_id = consents.tenant_id))))
    WHEN 'project'::text THEN (EXISTS ( SELECT 1
       FROM public.projects s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.organization_id = consents.tenant_id))))
    WHEN 'task'::text THEN (EXISTS ( SELECT 1
       FROM public.tasks s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.organization_id = consents.tenant_id))))
    ELSE COALESCE(better_supabase.can_subject(subject_type, subject_id, 'read'::text), false)
END) OR (grantor_id = ( SELECT auth.uid() AS uid))));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."consents"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (((tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('consents.read'::text) AS tenant_ids_with)) AND
CASE subject_type
    WHEN 'message'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.messages s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.read'::text) AS tenant_ids_with)))
    WHEN 'conversation'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.conversations s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.read'::text) AS tenant_ids_with)))
    WHEN 'channel'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.channels s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.read'::text) AS tenant_ids_with)))
    WHEN 'company'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.companies s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contacts.read'::text) AS tenant_ids_with)))
    WHEN 'person'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.people s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contacts.read'::text) AS tenant_ids_with)))
    WHEN 'deal'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.deals s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('deals.read'::text) AS tenant_ids_with)))
    WHEN 'course'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.courses s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('courses.read'::text) AS tenant_ids_with)))
    WHEN 'post'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.posts s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('posts.read'::text) AS tenant_ids_with)))
    WHEN 'activity'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.activities s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('activities.read'::text) AS tenant_ids_with)))
    WHEN 'quote'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.quotes s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('quotes.read'::text) AS tenant_ids_with)))
    WHEN 'work_item'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.work_items s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('tasks.read'::text) AS tenant_ids_with)))
    WHEN 'employee'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.employees s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('employees.read'::text) AS tenant_ids_with)))
    WHEN 'invoice'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.invoices s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('invoices.read'::text) AS tenant_ids_with)))
    WHEN 'ledger_account'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.ledger_accounts s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('ledger.read'::text) AS tenant_ids_with)))
    WHEN 'product'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.products s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'product_variant'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.product_variants s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'order'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.orders s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('orders.read'::text) AS tenant_ids_with)))
    WHEN 'calendar_event'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.calendar_events s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('calendar.read'::text) AS tenant_ids_with)))
    WHEN 'booking'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.bookings s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('bookings.read'::text) AS tenant_ids_with)))
    WHEN 'asset'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.assets s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('assets.read'::text) AS tenant_ids_with)))
    WHEN 'asset_location'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.asset_locations s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('assets.read'::text) AS tenant_ids_with)))
    WHEN 'lease'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.leases s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('leases.read'::text) AS tenant_ids_with)))
    WHEN 'expense_report'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.expense_reports s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('expenses.read'::text) AS tenant_ids_with)))
    WHEN 'expense_line'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.expense_lines s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('expenses.read'::text) AS tenant_ids_with)))
    WHEN 'donation_fund'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.donation_funds s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('donations.read'::text) AS tenant_ids_with)))
    WHEN 'work_order'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.work_orders s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('dispatch.read'::text) AS tenant_ids_with)))
    WHEN 'shipment'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.shipments s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('shipments.read'::text) AS tenant_ids_with)))
    WHEN 'contract'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.contracts s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contracts.read'::text) AS tenant_ids_with)))
    WHEN 'control'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.controls s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('compliance.read'::text) AS tenant_ids_with)))
    WHEN 'compliance_policy'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.compliance_policies s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('compliance.read'::text) AS tenant_ids_with)))
    WHEN 'qualification_type'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.qualification_types s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('qualifications.read'::text) AS tenant_ids_with)))
    WHEN 'risk'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.risks s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('risks.read'::text) AS tenant_ids_with)))
    WHEN 'case'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.cases s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('cases.read'::text) AS tenant_ids_with)))
    WHEN 'form'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.forms s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('forms.read'::text) AS tenant_ids_with)))
    WHEN 'tax_code'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.tax_codes s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('tax.read'::text) AS tenant_ids_with)))
    WHEN 'incident'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.incidents s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('incidents.read'::text) AS tenant_ids_with)))
    WHEN 'content_entry'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.content_entries s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('content.read'::text) AS tenant_ids_with)))
    WHEN 'document'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.documents s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('documents.read'::text) AS tenant_ids_with)))
    WHEN 'customer'::text THEN ((EXISTS ( SELECT 1
       FROM public.customers s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.organization_id = consents.tenant_id)))) AND
        ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('customers.read'::text) AS tenant_ids_with)) OR better_supabase.is_subject_member('customer'::text, subject_id)))
    WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.drive_nodes s
      WHERE
        ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id) AND (((consents.tenant_id IN ( SELECT better_supabase.tenant_ids_with('drive.read'::text) AS
        tenant_ids_with)) AND COALESCE(better_supabase.drive_node_readable(s.id), false)) OR better_supabase.is_subject_member('drive_node'::text, consents.subject_id)))))
    WHEN 'organization'::text THEN (EXISTS ( SELECT 1
       FROM public.organizations s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.id = consents.tenant_id))))
    WHEN 'application'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.applications s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('hiring.read'::text) AS tenant_ids_with)))
    WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
       FROM public.change_requests s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.organization_id = consents.tenant_id))))
    WHEN 'project'::text THEN (EXISTS ( SELECT 1
       FROM public.projects s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.organization_id = consents.tenant_id))))
    WHEN 'task'::text THEN (EXISTS ( SELECT 1
       FROM public.tasks s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.organization_id = consents.tenant_id))))
    ELSE COALESCE(better_supabase.can_subject(subject_type, subject_id, 'read'::text), false)
END) OR (grantor_id = ( SELECT auth.uid() AS uid)))));

CREATE POLICY "bsb_field_changes_read" ON "better_supabase"."field_changes"
  FOR SELECT
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.tenant_ids_with('field_history.read'::text) AS tenant_ids_with)) AND
CASE subject_type
    WHEN 'message'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.messages s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.read'::text) AS tenant_ids_with)))
    WHEN 'conversation'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.conversations s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.read'::text) AS tenant_ids_with)))
    WHEN 'channel'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.channels s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.read'::text) AS tenant_ids_with)))
    WHEN 'company'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.companies s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contacts.read'::text) AS tenant_ids_with)))
    WHEN 'person'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.people s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contacts.read'::text) AS tenant_ids_with)))
    WHEN 'deal'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.deals s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('deals.read'::text) AS tenant_ids_with)))
    WHEN 'course'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.courses s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('courses.read'::text) AS tenant_ids_with)))
    WHEN 'activity'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.activities s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('activities.read'::text) AS tenant_ids_with)))
    WHEN 'quote'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.quotes s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('quotes.read'::text) AS tenant_ids_with)))
    WHEN 'work_item'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.work_items s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('tasks.read'::text) AS tenant_ids_with)))
    WHEN 'employee'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.employees s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('employees.read'::text) AS tenant_ids_with)))
    WHEN 'invoice'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.invoices s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('invoices.read'::text) AS tenant_ids_with)))
    WHEN 'ledger_account'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.ledger_accounts s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('ledger.read'::text) AS tenant_ids_with)))
    WHEN 'product'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.products s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'product_variant'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.product_variants s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'order'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.orders s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('orders.read'::text) AS tenant_ids_with)))
    WHEN 'calendar_event'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.calendar_events s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('calendar.read'::text) AS tenant_ids_with)))
    WHEN 'booking'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.bookings s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('bookings.read'::text) AS tenant_ids_with)))
    WHEN 'asset'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.assets s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('assets.read'::text) AS tenant_ids_with)))
    WHEN 'asset_location'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.asset_locations s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('assets.read'::text) AS tenant_ids_with)))
    WHEN 'lease'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.leases s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('leases.read'::text) AS tenant_ids_with)))
    WHEN 'expense_report'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.expense_reports s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('expenses.read'::text) AS tenant_ids_with)))
    WHEN 'expense_line'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.expense_lines s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('expenses.read'::text) AS tenant_ids_with)))
    WHEN 'donation_fund'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.donation_funds s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('donations.read'::text) AS tenant_ids_with)))
    WHEN 'work_order'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.work_orders s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('dispatch.read'::text) AS tenant_ids_with)))
    WHEN 'shipment'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.shipments s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('shipments.read'::text) AS tenant_ids_with)))
    WHEN 'contract'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.contracts s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contracts.read'::text) AS tenant_ids_with)))
    WHEN 'control'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.controls s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('compliance.read'::text) AS tenant_ids_with)))
    WHEN 'compliance_policy'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.compliance_policies s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('compliance.read'::text) AS tenant_ids_with)))
    WHEN 'case'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.cases s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('cases.read'::text) AS tenant_ids_with)))
    WHEN 'form'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.forms s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('forms.read'::text) AS tenant_ids_with)))
    WHEN 'incident'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.incidents s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('incidents.read'::text) AS tenant_ids_with)))
    WHEN 'document'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.documents s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('documents.read'::text) AS tenant_ids_with)))
    WHEN 'customer'::text THEN ((EXISTS ( SELECT 1
       FROM public.customers s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.organization_id = field_changes.tenant_id)))) AND
        ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('customers.read'::text) AS tenant_ids_with)) OR better_supabase.is_subject_member('customer'::text, subject_id)))
    WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.drive_nodes s
      WHERE
        ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id) AND (((field_changes.tenant_id IN ( SELECT
        better_supabase.tenant_ids_with('drive.read'::text) AS tenant_ids_with)) AND COALESCE(better_supabase.drive_node_readable(s.id), false)) OR
        better_supabase.is_subject_member('drive_node'::text, field_changes.subject_id)))))
    WHEN 'organization'::text THEN (EXISTS ( SELECT 1
       FROM public.organizations s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.id = field_changes.tenant_id))))
    WHEN 'application'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.applications s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('hiring.read'::text) AS tenant_ids_with)))
    WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
       FROM public.change_requests s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.organization_id = field_changes.tenant_id))))
    WHEN 'project'::text THEN (EXISTS ( SELECT 1
       FROM public.projects s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.organization_id = field_changes.tenant_id))))
    WHEN 'task'::text THEN (EXISTS ( SELECT 1
       FROM public.tasks s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.organization_id = field_changes.tenant_id))))
    ELSE COALESCE(better_supabase.can_subject(subject_type, subject_id, 'read'::text), false)
END));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."field_changes"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('field_history.read'::text) AS tenant_ids_with)) AND
CASE subject_type
    WHEN 'message'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.messages s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.read'::text) AS tenant_ids_with)))
    WHEN 'conversation'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.conversations s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.read'::text) AS tenant_ids_with)))
    WHEN 'channel'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.channels s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.read'::text) AS tenant_ids_with)))
    WHEN 'company'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.companies s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contacts.read'::text) AS tenant_ids_with)))
    WHEN 'person'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.people s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contacts.read'::text) AS tenant_ids_with)))
    WHEN 'deal'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.deals s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('deals.read'::text) AS tenant_ids_with)))
    WHEN 'course'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.courses s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('courses.read'::text) AS tenant_ids_with)))
    WHEN 'activity'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.activities s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('activities.read'::text) AS tenant_ids_with)))
    WHEN 'quote'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.quotes s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('quotes.read'::text) AS tenant_ids_with)))
    WHEN 'work_item'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.work_items s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('tasks.read'::text) AS tenant_ids_with)))
    WHEN 'employee'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.employees s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('employees.read'::text) AS tenant_ids_with)))
    WHEN 'invoice'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.invoices s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('invoices.read'::text) AS tenant_ids_with)))
    WHEN 'ledger_account'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.ledger_accounts s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('ledger.read'::text) AS tenant_ids_with)))
    WHEN 'product'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.products s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'product_variant'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.product_variants s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'order'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.orders s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('orders.read'::text) AS tenant_ids_with)))
    WHEN 'calendar_event'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.calendar_events s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('calendar.read'::text) AS tenant_ids_with)))
    WHEN 'booking'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.bookings s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('bookings.read'::text) AS tenant_ids_with)))
    WHEN 'asset'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.assets s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('assets.read'::text) AS tenant_ids_with)))
    WHEN 'asset_location'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.asset_locations s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('assets.read'::text) AS tenant_ids_with)))
    WHEN 'lease'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.leases s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('leases.read'::text) AS tenant_ids_with)))
    WHEN 'expense_report'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.expense_reports s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('expenses.read'::text) AS tenant_ids_with)))
    WHEN 'expense_line'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.expense_lines s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('expenses.read'::text) AS tenant_ids_with)))
    WHEN 'donation_fund'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.donation_funds s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('donations.read'::text) AS tenant_ids_with)))
    WHEN 'work_order'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.work_orders s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('dispatch.read'::text) AS tenant_ids_with)))
    WHEN 'shipment'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.shipments s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('shipments.read'::text) AS tenant_ids_with)))
    WHEN 'contract'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.contracts s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contracts.read'::text) AS tenant_ids_with)))
    WHEN 'control'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.controls s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('compliance.read'::text) AS tenant_ids_with)))
    WHEN 'compliance_policy'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.compliance_policies s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('compliance.read'::text) AS tenant_ids_with)))
    WHEN 'case'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.cases s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('cases.read'::text) AS tenant_ids_with)))
    WHEN 'form'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.forms s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('forms.read'::text) AS tenant_ids_with)))
    WHEN 'incident'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.incidents s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('incidents.read'::text) AS tenant_ids_with)))
    WHEN 'document'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.documents s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('documents.read'::text) AS tenant_ids_with)))
    WHEN 'customer'::text THEN ((EXISTS ( SELECT 1
       FROM public.customers s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.organization_id = field_changes.tenant_id)))) AND
        ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('customers.read'::text) AS tenant_ids_with)) OR better_supabase.is_subject_member('customer'::text, subject_id)))
    WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.drive_nodes s
      WHERE
        ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id) AND (((field_changes.tenant_id IN ( SELECT
        better_supabase.tenant_ids_with('drive.read'::text) AS tenant_ids_with)) AND COALESCE(better_supabase.drive_node_readable(s.id), false)) OR
        better_supabase.is_subject_member('drive_node'::text, field_changes.subject_id)))))
    WHEN 'organization'::text THEN (EXISTS ( SELECT 1
       FROM public.organizations s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.id = field_changes.tenant_id))))
    WHEN 'application'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.applications s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('hiring.read'::text) AS tenant_ids_with)))
    WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
       FROM public.change_requests s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.organization_id = field_changes.tenant_id))))
    WHEN 'project'::text THEN (EXISTS ( SELECT 1
       FROM public.projects s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.organization_id = field_changes.tenant_id))))
    WHEN 'task'::text THEN (EXISTS ( SELECT 1
       FROM public.tasks s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.organization_id = field_changes.tenant_id))))
    ELSE COALESCE(better_supabase.can_subject(subject_type, subject_id, 'read'::text), false)
END)));

CREATE POLICY "bsb_funding_awards_read" ON "better_supabase"."funding_awards"
  FOR SELECT
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.tenant_ids_with('funding.read'::text) AS tenant_ids_with)) AND
CASE subject_type
    WHEN 'message'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.messages s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.read'::text) AS tenant_ids_with)))
    WHEN 'conversation'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.conversations s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.read'::text) AS tenant_ids_with)))
    WHEN 'channel'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.channels s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.read'::text) AS tenant_ids_with)))
    WHEN 'company'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.companies s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contacts.read'::text) AS tenant_ids_with)))
    WHEN 'person'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.people s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contacts.read'::text) AS tenant_ids_with)))
    WHEN 'deal'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.deals s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('deals.read'::text) AS tenant_ids_with)))
    WHEN 'course'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.courses s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('courses.read'::text) AS tenant_ids_with)))
    WHEN 'post'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.posts s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('posts.read'::text) AS tenant_ids_with)))
    WHEN 'activity'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.activities s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('activities.read'::text) AS tenant_ids_with)))
    WHEN 'quote'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.quotes s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('quotes.read'::text) AS tenant_ids_with)))
    WHEN 'work_item'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.work_items s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('tasks.read'::text) AS tenant_ids_with)))
    WHEN 'employee'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.employees s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('employees.read'::text) AS tenant_ids_with)))
    WHEN 'invoice'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.invoices s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('invoices.read'::text) AS tenant_ids_with)))
    WHEN 'ledger_account'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.ledger_accounts s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('ledger.read'::text) AS tenant_ids_with)))
    WHEN 'product'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.products s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'product_variant'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.product_variants s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'order'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.orders s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('orders.read'::text) AS tenant_ids_with)))
    WHEN 'calendar_event'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.calendar_events s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('calendar.read'::text) AS tenant_ids_with)))
    WHEN 'booking'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.bookings s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('bookings.read'::text) AS tenant_ids_with)))
    WHEN 'asset'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.assets s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('assets.read'::text) AS tenant_ids_with)))
    WHEN 'asset_location'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.asset_locations s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('assets.read'::text) AS tenant_ids_with)))
    WHEN 'lease'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.leases s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('leases.read'::text) AS tenant_ids_with)))
    WHEN 'expense_report'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.expense_reports s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('expenses.read'::text) AS tenant_ids_with)))
    WHEN 'expense_line'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.expense_lines s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('expenses.read'::text) AS tenant_ids_with)))
    WHEN 'donation_fund'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.donation_funds s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('donations.read'::text) AS tenant_ids_with)))
    WHEN 'work_order'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.work_orders s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('dispatch.read'::text) AS tenant_ids_with)))
    WHEN 'shipment'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.shipments s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('shipments.read'::text) AS tenant_ids_with)))
    WHEN 'contract'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.contracts s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contracts.read'::text) AS tenant_ids_with)))
    WHEN 'control'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.controls s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('compliance.read'::text) AS tenant_ids_with)))
    WHEN 'compliance_policy'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.compliance_policies s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('compliance.read'::text) AS tenant_ids_with)))
    WHEN 'qualification_type'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.qualification_types s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('qualifications.read'::text) AS tenant_ids_with)))
    WHEN 'risk'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.risks s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('risks.read'::text) AS tenant_ids_with)))
    WHEN 'case'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.cases s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('cases.read'::text) AS tenant_ids_with)))
    WHEN 'inspection'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.inspections s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('inspections.read'::text) AS tenant_ids_with)))
    WHEN 'inspection_program'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.inspection_programs s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('inspections.read'::text) AS tenant_ids_with)))
    WHEN 'inspection_finding'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.inspection_findings s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('inspections.read'::text) AS tenant_ids_with)))
    WHEN 'form'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.forms s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('forms.read'::text) AS tenant_ids_with)))
    WHEN 'meeting'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.meetings s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('meetings.read'::text) AS tenant_ids_with)))
    WHEN 'meeting_decision'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.meeting_decisions s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('meetings.read'::text) AS tenant_ids_with)))
    WHEN 'tax_code'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.tax_codes s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('tax.read'::text) AS tenant_ids_with)))
    WHEN 'production_order'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.production_orders s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('manufacturing.read'::text) AS tenant_ids_with)))
    WHEN 'work_center'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.work_centers s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('manufacturing.read'::text) AS tenant_ids_with)))
    WHEN 'bank_account'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.bank_accounts s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('banking.read'::text) AS tenant_ids_with)))
    WHEN 'care_plan'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.care_plans s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('care_plans.read'::text) AS tenant_ids_with)))
    WHEN 'incident'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.incidents s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('incidents.read'::text) AS tenant_ids_with)))
    WHEN 'content_entry'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.content_entries s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('content.read'::text) AS tenant_ids_with)))
    WHEN 'document'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.documents s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('documents.read'::text) AS tenant_ids_with)))
    WHEN 'customer'::text THEN ((EXISTS ( SELECT 1
       FROM public.customers s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.organization_id = funding_awards.tenant_id)))) AND
        ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('customers.read'::text) AS tenant_ids_with)) OR better_supabase.is_subject_member('customer'::text, subject_id)))
    WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.drive_nodes s
      WHERE
        ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id) AND (((funding_awards.tenant_id IN ( SELECT
        better_supabase.tenant_ids_with('drive.read'::text) AS tenant_ids_with)) AND COALESCE(better_supabase.drive_node_readable(s.id), false)) OR
        better_supabase.is_subject_member('drive_node'::text, funding_awards.subject_id)))))
    WHEN 'organization'::text THEN (EXISTS ( SELECT 1
       FROM public.organizations s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.id = funding_awards.tenant_id))))
    WHEN 'application'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.applications s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('hiring.read'::text) AS tenant_ids_with)))
    WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
       FROM public.change_requests s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.organization_id = funding_awards.tenant_id))))
    WHEN 'project'::text THEN (EXISTS ( SELECT 1
       FROM public.projects s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.organization_id = funding_awards.tenant_id))))
    WHEN 'task'::text THEN (EXISTS ( SELECT 1
       FROM public.tasks s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.organization_id = funding_awards.tenant_id))))
    ELSE COALESCE(better_supabase.can_subject(subject_type, subject_id, 'read'::text), false)
END));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."funding_awards"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('funding.read'::text)
    AS tenant_ids_with)) AND
CASE subject_type
    WHEN 'message'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.messages s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.read'::text) AS tenant_ids_with)))
    WHEN 'conversation'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.conversations s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.read'::text) AS tenant_ids_with)))
    WHEN 'channel'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.channels s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.read'::text) AS tenant_ids_with)))
    WHEN 'company'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.companies s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contacts.read'::text) AS tenant_ids_with)))
    WHEN 'person'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.people s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contacts.read'::text) AS tenant_ids_with)))
    WHEN 'deal'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.deals s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('deals.read'::text) AS tenant_ids_with)))
    WHEN 'course'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.courses s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('courses.read'::text) AS tenant_ids_with)))
    WHEN 'post'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.posts s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('posts.read'::text) AS tenant_ids_with)))
    WHEN 'activity'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.activities s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('activities.read'::text) AS tenant_ids_with)))
    WHEN 'quote'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.quotes s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('quotes.read'::text) AS tenant_ids_with)))
    WHEN 'work_item'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.work_items s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('tasks.read'::text) AS tenant_ids_with)))
    WHEN 'employee'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.employees s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('employees.read'::text) AS tenant_ids_with)))
    WHEN 'invoice'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.invoices s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('invoices.read'::text) AS tenant_ids_with)))
    WHEN 'ledger_account'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.ledger_accounts s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('ledger.read'::text) AS tenant_ids_with)))
    WHEN 'product'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.products s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'product_variant'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.product_variants s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'order'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.orders s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('orders.read'::text) AS tenant_ids_with)))
    WHEN 'calendar_event'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.calendar_events s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('calendar.read'::text) AS tenant_ids_with)))
    WHEN 'booking'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.bookings s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('bookings.read'::text) AS tenant_ids_with)))
    WHEN 'asset'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.assets s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('assets.read'::text) AS tenant_ids_with)))
    WHEN 'asset_location'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.asset_locations s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('assets.read'::text) AS tenant_ids_with)))
    WHEN 'lease'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.leases s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('leases.read'::text) AS tenant_ids_with)))
    WHEN 'expense_report'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.expense_reports s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('expenses.read'::text) AS tenant_ids_with)))
    WHEN 'expense_line'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.expense_lines s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('expenses.read'::text) AS tenant_ids_with)))
    WHEN 'donation_fund'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.donation_funds s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('donations.read'::text) AS tenant_ids_with)))
    WHEN 'work_order'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.work_orders s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('dispatch.read'::text) AS tenant_ids_with)))
    WHEN 'shipment'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.shipments s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('shipments.read'::text) AS tenant_ids_with)))
    WHEN 'contract'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.contracts s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contracts.read'::text) AS tenant_ids_with)))
    WHEN 'control'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.controls s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('compliance.read'::text) AS tenant_ids_with)))
    WHEN 'compliance_policy'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.compliance_policies s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('compliance.read'::text) AS tenant_ids_with)))
    WHEN 'qualification_type'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.qualification_types s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('qualifications.read'::text) AS tenant_ids_with)))
    WHEN 'risk'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.risks s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('risks.read'::text) AS tenant_ids_with)))
    WHEN 'case'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.cases s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('cases.read'::text) AS tenant_ids_with)))
    WHEN 'inspection'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.inspections s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('inspections.read'::text) AS tenant_ids_with)))
    WHEN 'inspection_program'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.inspection_programs s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('inspections.read'::text) AS tenant_ids_with)))
    WHEN 'inspection_finding'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.inspection_findings s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('inspections.read'::text) AS tenant_ids_with)))
    WHEN 'form'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.forms s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('forms.read'::text) AS tenant_ids_with)))
    WHEN 'meeting'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.meetings s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('meetings.read'::text) AS tenant_ids_with)))
    WHEN 'meeting_decision'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.meeting_decisions s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('meetings.read'::text) AS tenant_ids_with)))
    WHEN 'tax_code'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.tax_codes s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('tax.read'::text) AS tenant_ids_with)))
    WHEN 'production_order'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.production_orders s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('manufacturing.read'::text) AS tenant_ids_with)))
    WHEN 'work_center'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.work_centers s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('manufacturing.read'::text) AS tenant_ids_with)))
    WHEN 'bank_account'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.bank_accounts s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('banking.read'::text) AS tenant_ids_with)))
    WHEN 'care_plan'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.care_plans s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('care_plans.read'::text) AS tenant_ids_with)))
    WHEN 'incident'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.incidents s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('incidents.read'::text) AS tenant_ids_with)))
    WHEN 'content_entry'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.content_entries s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('content.read'::text) AS tenant_ids_with)))
    WHEN 'document'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.documents s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('documents.read'::text) AS tenant_ids_with)))
    WHEN 'customer'::text THEN ((EXISTS ( SELECT 1
       FROM public.customers s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.organization_id = funding_awards.tenant_id)))) AND
        ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('customers.read'::text) AS tenant_ids_with)) OR better_supabase.is_subject_member('customer'::text, subject_id)))
    WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.drive_nodes s
      WHERE
        ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id) AND (((funding_awards.tenant_id IN ( SELECT
        better_supabase.tenant_ids_with('drive.read'::text) AS tenant_ids_with)) AND COALESCE(better_supabase.drive_node_readable(s.id), false)) OR
        better_supabase.is_subject_member('drive_node'::text, funding_awards.subject_id)))))
    WHEN 'organization'::text THEN (EXISTS ( SELECT 1
       FROM public.organizations s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.id = funding_awards.tenant_id))))
    WHEN 'application'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.applications s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('hiring.read'::text) AS tenant_ids_with)))
    WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
       FROM public.change_requests s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.organization_id = funding_awards.tenant_id))))
    WHEN 'project'::text THEN (EXISTS ( SELECT 1
       FROM public.projects s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.organization_id = funding_awards.tenant_id))))
    WHEN 'task'::text THEN (EXISTS ( SELECT 1
       FROM public.tasks s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.organization_id = funding_awards.tenant_id))))
    ELSE COALESCE(better_supabase.can_subject(subject_type, subject_id, 'read'::text), false)
END)));

CREATE POLICY "bsb_medication_orders_read" ON "better_supabase"."medication_orders"
  FOR SELECT
  TO "authenticated"
  USING ((((tenant_id IN ( SELECT better_supabase.tenant_ids_with('medications.read'::text) AS tenant_ids_with)) AND
CASE subject_type
    WHEN 'message'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.messages s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.read'::text) AS tenant_ids_with)))
    WHEN 'conversation'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.conversations s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.read'::text) AS tenant_ids_with)))
    WHEN 'channel'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.channels s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.read'::text) AS tenant_ids_with)))
    WHEN 'company'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.companies s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contacts.read'::text) AS tenant_ids_with)))
    WHEN 'person'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.people s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contacts.read'::text) AS tenant_ids_with)))
    WHEN 'deal'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.deals s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('deals.read'::text) AS tenant_ids_with)))
    WHEN 'course'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.courses s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('courses.read'::text) AS tenant_ids_with)))
    WHEN 'post'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.posts s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('posts.read'::text) AS tenant_ids_with)))
    WHEN 'activity'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.activities s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('activities.read'::text) AS tenant_ids_with)))
    WHEN 'quote'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.quotes s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('quotes.read'::text) AS tenant_ids_with)))
    WHEN 'work_item'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.work_items s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('tasks.read'::text) AS tenant_ids_with)))
    WHEN 'employee'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.employees s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('employees.read'::text) AS tenant_ids_with)))
    WHEN 'invoice'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.invoices s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('invoices.read'::text) AS tenant_ids_with)))
    WHEN 'ledger_account'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.ledger_accounts s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('ledger.read'::text) AS tenant_ids_with)))
    WHEN 'product'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.products s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'product_variant'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.product_variants s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'order'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.orders s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('orders.read'::text) AS tenant_ids_with)))
    WHEN 'calendar_event'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.calendar_events s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('calendar.read'::text) AS tenant_ids_with)))
    WHEN 'booking'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.bookings s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('bookings.read'::text) AS tenant_ids_with)))
    WHEN 'asset'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.assets s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('assets.read'::text) AS tenant_ids_with)))
    WHEN 'asset_location'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.asset_locations s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('assets.read'::text) AS tenant_ids_with)))
    WHEN 'lease'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.leases s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('leases.read'::text) AS tenant_ids_with)))
    WHEN 'expense_report'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.expense_reports s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('expenses.read'::text) AS tenant_ids_with)))
    WHEN 'expense_line'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.expense_lines s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('expenses.read'::text) AS tenant_ids_with)))
    WHEN 'donation_fund'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.donation_funds s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('donations.read'::text) AS tenant_ids_with)))
    WHEN 'work_order'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.work_orders s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('dispatch.read'::text) AS tenant_ids_with)))
    WHEN 'shipment'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.shipments s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('shipments.read'::text) AS tenant_ids_with)))
    WHEN 'contract'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.contracts s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contracts.read'::text) AS tenant_ids_with)))
    WHEN 'control'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.controls s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('compliance.read'::text) AS tenant_ids_with)))
    WHEN 'compliance_policy'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.compliance_policies s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('compliance.read'::text) AS tenant_ids_with)))
    WHEN 'qualification_type'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.qualification_types s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('qualifications.read'::text) AS tenant_ids_with)))
    WHEN 'risk'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.risks s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('risks.read'::text) AS tenant_ids_with)))
    WHEN 'case'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.cases s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('cases.read'::text) AS tenant_ids_with)))
    WHEN 'form'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.forms s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('forms.read'::text) AS tenant_ids_with)))
    WHEN 'tax_code'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.tax_codes s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('tax.read'::text) AS tenant_ids_with)))
    WHEN 'incident'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.incidents s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('incidents.read'::text) AS tenant_ids_with)))
    WHEN 'content_entry'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.content_entries s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('content.read'::text) AS tenant_ids_with)))
    WHEN 'document'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.documents s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('documents.read'::text) AS tenant_ids_with)))
    WHEN 'customer'::text THEN ((EXISTS ( SELECT 1
       FROM public.customers s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.organization_id = medication_orders.tenant_id)))) AND
        ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('customers.read'::text) AS tenant_ids_with)) OR better_supabase.is_subject_member('customer'::text, subject_id)))
    WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.drive_nodes s
      WHERE
        ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id) AND (((medication_orders.tenant_id IN ( SELECT
        better_supabase.tenant_ids_with('drive.read'::text) AS tenant_ids_with)) AND COALESCE(better_supabase.drive_node_readable(s.id), false)) OR
        better_supabase.is_subject_member('drive_node'::text, medication_orders.subject_id)))))
    WHEN 'organization'::text THEN (EXISTS ( SELECT 1
       FROM public.organizations s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.id = medication_orders.tenant_id))))
    WHEN 'application'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.applications s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('hiring.read'::text) AS tenant_ids_with)))
    WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
       FROM public.change_requests s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.organization_id = medication_orders.tenant_id))))
    WHEN 'project'::text THEN (EXISTS ( SELECT 1
       FROM public.projects s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.organization_id = medication_orders.tenant_id))))
    WHEN 'task'::text THEN (EXISTS ( SELECT 1
       FROM public.tasks s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.organization_id = medication_orders.tenant_id))))
    ELSE COALESCE(better_supabase.can_subject(subject_type, subject_id, 'read'::text), false)
END) OR (((tenant_id)::text, subject_type, subject_id) IN ( SELECT g.tenant,
    g.subject_type,
    g.subject_id
   FROM better_supabase.portal_subjects('read'::text) g(tenant, subject_type, subject_id)))));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."medication_orders"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (((tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('medications.read'::text) AS tenant_ids_with)) AND
CASE subject_type
    WHEN 'message'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.messages s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.read'::text) AS tenant_ids_with)))
    WHEN 'conversation'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.conversations s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.read'::text) AS tenant_ids_with)))
    WHEN 'channel'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.channels s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.read'::text) AS tenant_ids_with)))
    WHEN 'company'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.companies s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contacts.read'::text) AS tenant_ids_with)))
    WHEN 'person'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.people s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contacts.read'::text) AS tenant_ids_with)))
    WHEN 'deal'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.deals s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('deals.read'::text) AS tenant_ids_with)))
    WHEN 'course'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.courses s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('courses.read'::text) AS tenant_ids_with)))
    WHEN 'post'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.posts s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('posts.read'::text) AS tenant_ids_with)))
    WHEN 'activity'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.activities s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('activities.read'::text) AS tenant_ids_with)))
    WHEN 'quote'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.quotes s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('quotes.read'::text) AS tenant_ids_with)))
    WHEN 'work_item'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.work_items s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('tasks.read'::text) AS tenant_ids_with)))
    WHEN 'employee'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.employees s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('employees.read'::text) AS tenant_ids_with)))
    WHEN 'invoice'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.invoices s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('invoices.read'::text) AS tenant_ids_with)))
    WHEN 'ledger_account'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.ledger_accounts s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('ledger.read'::text) AS tenant_ids_with)))
    WHEN 'product'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.products s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'product_variant'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.product_variants s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'order'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.orders s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('orders.read'::text) AS tenant_ids_with)))
    WHEN 'calendar_event'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.calendar_events s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('calendar.read'::text) AS tenant_ids_with)))
    WHEN 'booking'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.bookings s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('bookings.read'::text) AS tenant_ids_with)))
    WHEN 'asset'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.assets s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('assets.read'::text) AS tenant_ids_with)))
    WHEN 'asset_location'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.asset_locations s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('assets.read'::text) AS tenant_ids_with)))
    WHEN 'lease'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.leases s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('leases.read'::text) AS tenant_ids_with)))
    WHEN 'expense_report'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.expense_reports s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('expenses.read'::text) AS tenant_ids_with)))
    WHEN 'expense_line'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.expense_lines s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('expenses.read'::text) AS tenant_ids_with)))
    WHEN 'donation_fund'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.donation_funds s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('donations.read'::text) AS tenant_ids_with)))
    WHEN 'work_order'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.work_orders s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('dispatch.read'::text) AS tenant_ids_with)))
    WHEN 'shipment'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.shipments s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('shipments.read'::text) AS tenant_ids_with)))
    WHEN 'contract'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.contracts s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contracts.read'::text) AS tenant_ids_with)))
    WHEN 'control'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.controls s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('compliance.read'::text) AS tenant_ids_with)))
    WHEN 'compliance_policy'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.compliance_policies s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('compliance.read'::text) AS tenant_ids_with)))
    WHEN 'qualification_type'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.qualification_types s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('qualifications.read'::text) AS tenant_ids_with)))
    WHEN 'risk'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.risks s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('risks.read'::text) AS tenant_ids_with)))
    WHEN 'case'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.cases s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('cases.read'::text) AS tenant_ids_with)))
    WHEN 'form'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.forms s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('forms.read'::text) AS tenant_ids_with)))
    WHEN 'tax_code'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.tax_codes s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('tax.read'::text) AS tenant_ids_with)))
    WHEN 'incident'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.incidents s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('incidents.read'::text) AS tenant_ids_with)))
    WHEN 'content_entry'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.content_entries s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('content.read'::text) AS tenant_ids_with)))
    WHEN 'document'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.documents s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('documents.read'::text) AS tenant_ids_with)))
    WHEN 'customer'::text THEN ((EXISTS ( SELECT 1
       FROM public.customers s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.organization_id = medication_orders.tenant_id)))) AND
        ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('customers.read'::text) AS tenant_ids_with)) OR better_supabase.is_subject_member('customer'::text, subject_id)))
    WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.drive_nodes s
      WHERE
        ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id) AND (((medication_orders.tenant_id IN ( SELECT
        better_supabase.tenant_ids_with('drive.read'::text) AS tenant_ids_with)) AND COALESCE(better_supabase.drive_node_readable(s.id), false)) OR
        better_supabase.is_subject_member('drive_node'::text, medication_orders.subject_id)))))
    WHEN 'organization'::text THEN (EXISTS ( SELECT 1
       FROM public.organizations s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.id = medication_orders.tenant_id))))
    WHEN 'application'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.applications s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('hiring.read'::text) AS tenant_ids_with)))
    WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
       FROM public.change_requests s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.organization_id = medication_orders.tenant_id))))
    WHEN 'project'::text THEN (EXISTS ( SELECT 1
       FROM public.projects s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.organization_id = medication_orders.tenant_id))))
    WHEN 'task'::text THEN (EXISTS ( SELECT 1
       FROM public.tasks s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.organization_id = medication_orders.tenant_id))))
    ELSE COALESCE(better_supabase.can_subject(subject_type, subject_id, 'read'::text), false)
END) OR (((tenant_id)::text, subject_type, subject_id) IN ( SELECT g.tenant,
    g.subject_type,
    g.subject_id
   FROM better_supabase.portal_subjects('read'::text) g(tenant, subject_type, subject_id))))));

CREATE POLICY "bsb_observations_read" ON "better_supabase"."observations"
  FOR SELECT
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.tenant_ids_with('observations.read'::text) AS tenant_ids_with)) AND
CASE subject_type
    WHEN 'message'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.messages s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.read'::text) AS tenant_ids_with)))
    WHEN 'conversation'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.conversations s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.read'::text) AS tenant_ids_with)))
    WHEN 'channel'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.channels s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.read'::text) AS tenant_ids_with)))
    WHEN 'company'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.companies s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contacts.read'::text) AS tenant_ids_with)))
    WHEN 'person'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.people s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contacts.read'::text) AS tenant_ids_with)))
    WHEN 'deal'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.deals s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('deals.read'::text) AS tenant_ids_with)))
    WHEN 'course'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.courses s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('courses.read'::text) AS tenant_ids_with)))
    WHEN 'post'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.posts s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('posts.read'::text) AS tenant_ids_with)))
    WHEN 'activity'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.activities s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('activities.read'::text) AS tenant_ids_with)))
    WHEN 'quote'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.quotes s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('quotes.read'::text) AS tenant_ids_with)))
    WHEN 'work_item'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.work_items s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('tasks.read'::text) AS tenant_ids_with)))
    WHEN 'employee'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.employees s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('employees.read'::text) AS tenant_ids_with)))
    WHEN 'invoice'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.invoices s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('invoices.read'::text) AS tenant_ids_with)))
    WHEN 'ledger_account'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.ledger_accounts s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('ledger.read'::text) AS tenant_ids_with)))
    WHEN 'product'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.products s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'product_variant'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.product_variants s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'order'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.orders s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('orders.read'::text) AS tenant_ids_with)))
    WHEN 'calendar_event'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.calendar_events s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('calendar.read'::text) AS tenant_ids_with)))
    WHEN 'booking'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.bookings s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('bookings.read'::text) AS tenant_ids_with)))
    WHEN 'asset'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.assets s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('assets.read'::text) AS tenant_ids_with)))
    WHEN 'asset_location'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.asset_locations s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('assets.read'::text) AS tenant_ids_with)))
    WHEN 'lease'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.leases s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('leases.read'::text) AS tenant_ids_with)))
    WHEN 'expense_report'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.expense_reports s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('expenses.read'::text) AS tenant_ids_with)))
    WHEN 'expense_line'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.expense_lines s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('expenses.read'::text) AS tenant_ids_with)))
    WHEN 'donation_fund'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.donation_funds s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('donations.read'::text) AS tenant_ids_with)))
    WHEN 'work_order'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.work_orders s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('dispatch.read'::text) AS tenant_ids_with)))
    WHEN 'shipment'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.shipments s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('shipments.read'::text) AS tenant_ids_with)))
    WHEN 'contract'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.contracts s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contracts.read'::text) AS tenant_ids_with)))
    WHEN 'control'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.controls s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('compliance.read'::text) AS tenant_ids_with)))
    WHEN 'compliance_policy'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.compliance_policies s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('compliance.read'::text) AS tenant_ids_with)))
    WHEN 'qualification_type'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.qualification_types s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('qualifications.read'::text) AS tenant_ids_with)))
    WHEN 'risk'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.risks s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('risks.read'::text) AS tenant_ids_with)))
    WHEN 'case'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.cases s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('cases.read'::text) AS tenant_ids_with)))
    WHEN 'form'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.forms s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('forms.read'::text) AS tenant_ids_with)))
    WHEN 'tax_code'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.tax_codes s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('tax.read'::text) AS tenant_ids_with)))
    WHEN 'incident'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.incidents s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('incidents.read'::text) AS tenant_ids_with)))
    WHEN 'content_entry'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.content_entries s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('content.read'::text) AS tenant_ids_with)))
    WHEN 'document'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.documents s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('documents.read'::text) AS tenant_ids_with)))
    WHEN 'customer'::text THEN ((EXISTS ( SELECT 1
       FROM public.customers s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.organization_id = observations.tenant_id)))) AND
        ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('customers.read'::text) AS tenant_ids_with)) OR better_supabase.is_subject_member('customer'::text, subject_id)))
    WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.drive_nodes s
      WHERE
        ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id) AND (((observations.tenant_id IN ( SELECT
        better_supabase.tenant_ids_with('drive.read'::text) AS tenant_ids_with)) AND COALESCE(better_supabase.drive_node_readable(s.id), false)) OR
        better_supabase.is_subject_member('drive_node'::text, observations.subject_id)))))
    WHEN 'organization'::text THEN (EXISTS ( SELECT 1
       FROM public.organizations s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.id = observations.tenant_id))))
    WHEN 'application'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.applications s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('hiring.read'::text) AS tenant_ids_with)))
    WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
       FROM public.change_requests s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.organization_id = observations.tenant_id))))
    WHEN 'project'::text THEN (EXISTS ( SELECT 1
       FROM public.projects s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.organization_id = observations.tenant_id))))
    WHEN 'task'::text THEN (EXISTS ( SELECT 1
       FROM public.tasks s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.organization_id = observations.tenant_id))))
    ELSE COALESCE(better_supabase.can_subject(subject_type, subject_id, 'read'::text), false)
END));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."observations"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('observations.read'::text) AS tenant_ids_with)) AND
CASE subject_type
    WHEN 'message'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.messages s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.read'::text) AS tenant_ids_with)))
    WHEN 'conversation'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.conversations s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.read'::text) AS tenant_ids_with)))
    WHEN 'channel'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.channels s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.read'::text) AS tenant_ids_with)))
    WHEN 'company'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.companies s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contacts.read'::text) AS tenant_ids_with)))
    WHEN 'person'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.people s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contacts.read'::text) AS tenant_ids_with)))
    WHEN 'deal'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.deals s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('deals.read'::text) AS tenant_ids_with)))
    WHEN 'course'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.courses s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('courses.read'::text) AS tenant_ids_with)))
    WHEN 'post'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.posts s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('posts.read'::text) AS tenant_ids_with)))
    WHEN 'activity'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.activities s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('activities.read'::text) AS tenant_ids_with)))
    WHEN 'quote'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.quotes s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('quotes.read'::text) AS tenant_ids_with)))
    WHEN 'work_item'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.work_items s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('tasks.read'::text) AS tenant_ids_with)))
    WHEN 'employee'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.employees s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('employees.read'::text) AS tenant_ids_with)))
    WHEN 'invoice'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.invoices s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('invoices.read'::text) AS tenant_ids_with)))
    WHEN 'ledger_account'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.ledger_accounts s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('ledger.read'::text) AS tenant_ids_with)))
    WHEN 'product'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.products s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'product_variant'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.product_variants s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'order'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.orders s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('orders.read'::text) AS tenant_ids_with)))
    WHEN 'calendar_event'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.calendar_events s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('calendar.read'::text) AS tenant_ids_with)))
    WHEN 'booking'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.bookings s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('bookings.read'::text) AS tenant_ids_with)))
    WHEN 'asset'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.assets s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('assets.read'::text) AS tenant_ids_with)))
    WHEN 'asset_location'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.asset_locations s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('assets.read'::text) AS tenant_ids_with)))
    WHEN 'lease'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.leases s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('leases.read'::text) AS tenant_ids_with)))
    WHEN 'expense_report'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.expense_reports s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('expenses.read'::text) AS tenant_ids_with)))
    WHEN 'expense_line'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.expense_lines s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('expenses.read'::text) AS tenant_ids_with)))
    WHEN 'donation_fund'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.donation_funds s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('donations.read'::text) AS tenant_ids_with)))
    WHEN 'work_order'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.work_orders s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('dispatch.read'::text) AS tenant_ids_with)))
    WHEN 'shipment'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.shipments s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('shipments.read'::text) AS tenant_ids_with)))
    WHEN 'contract'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.contracts s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contracts.read'::text) AS tenant_ids_with)))
    WHEN 'control'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.controls s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('compliance.read'::text) AS tenant_ids_with)))
    WHEN 'compliance_policy'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.compliance_policies s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('compliance.read'::text) AS tenant_ids_with)))
    WHEN 'qualification_type'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.qualification_types s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('qualifications.read'::text) AS tenant_ids_with)))
    WHEN 'risk'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.risks s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('risks.read'::text) AS tenant_ids_with)))
    WHEN 'case'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.cases s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('cases.read'::text) AS tenant_ids_with)))
    WHEN 'form'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.forms s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('forms.read'::text) AS tenant_ids_with)))
    WHEN 'tax_code'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.tax_codes s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('tax.read'::text) AS tenant_ids_with)))
    WHEN 'incident'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.incidents s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('incidents.read'::text) AS tenant_ids_with)))
    WHEN 'content_entry'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.content_entries s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('content.read'::text) AS tenant_ids_with)))
    WHEN 'document'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.documents s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('documents.read'::text) AS tenant_ids_with)))
    WHEN 'customer'::text THEN ((EXISTS ( SELECT 1
       FROM public.customers s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.organization_id = observations.tenant_id)))) AND
        ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('customers.read'::text) AS tenant_ids_with)) OR better_supabase.is_subject_member('customer'::text, subject_id)))
    WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.drive_nodes s
      WHERE
        ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id) AND (((observations.tenant_id IN ( SELECT
        better_supabase.tenant_ids_with('drive.read'::text) AS tenant_ids_with)) AND COALESCE(better_supabase.drive_node_readable(s.id), false)) OR
        better_supabase.is_subject_member('drive_node'::text, observations.subject_id)))))
    WHEN 'organization'::text THEN (EXISTS ( SELECT 1
       FROM public.organizations s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.id = observations.tenant_id))))
    WHEN 'application'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.applications s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('hiring.read'::text) AS tenant_ids_with)))
    WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
       FROM public.change_requests s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.organization_id = observations.tenant_id))))
    WHEN 'project'::text THEN (EXISTS ( SELECT 1
       FROM public.projects s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.organization_id = observations.tenant_id))))
    WHEN 'task'::text THEN (EXISTS ( SELECT 1
       FROM public.tasks s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.organization_id = observations.tenant_id))))
    ELSE COALESCE(better_supabase.can_subject(subject_type, subject_id, 'read'::text), false)
END)));

CREATE POLICY "bsb_pipeline_stage_history_read" ON "better_supabase"."pipeline_stage_history"
  FOR SELECT
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.tenant_ids_with('pipelines.read'::text) AS tenant_ids_with)) AND
CASE subject_type
    WHEN 'deal'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.deals s
      WHERE ((s.id = (pipeline_stage_history.subject_id)::uuid) AND (s.tenant_id = pipeline_stage_history.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('deals.read'::text) AS tenant_ids_with)))
    WHEN 'work_item'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.work_items s
      WHERE ((s.id = (pipeline_stage_history.subject_id)::uuid) AND (s.tenant_id = pipeline_stage_history.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('tasks.read'::text) AS tenant_ids_with)))
    WHEN 'ledger_account'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.ledger_accounts s
      WHERE ((s.id = (pipeline_stage_history.subject_id)::uuid) AND (s.tenant_id = pipeline_stage_history.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('ledger.read'::text) AS tenant_ids_with)))
    WHEN 'product'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.products s
      WHERE ((s.id = (pipeline_stage_history.subject_id)::uuid) AND (s.tenant_id = pipeline_stage_history.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'product_variant'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.product_variants s
      WHERE ((s.id = (pipeline_stage_history.subject_id)::uuid) AND (s.tenant_id = pipeline_stage_history.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'order'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.orders s
      WHERE ((s.id = (pipeline_stage_history.subject_id)::uuid) AND (s.tenant_id = pipeline_stage_history.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('orders.read'::text) AS tenant_ids_with)))
    WHEN 'calendar_event'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.calendar_events s
      WHERE ((s.id = (pipeline_stage_history.subject_id)::uuid) AND (s.tenant_id = pipeline_stage_history.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('calendar.read'::text) AS tenant_ids_with)))
    WHEN 'booking'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.bookings s
      WHERE ((s.id = (pipeline_stage_history.subject_id)::uuid) AND (s.tenant_id = pipeline_stage_history.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('bookings.read'::text) AS tenant_ids_with)))
    WHEN 'case'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.cases s
      WHERE ((s.id = (pipeline_stage_history.subject_id)::uuid) AND (s.tenant_id = pipeline_stage_history.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('cases.read'::text) AS tenant_ids_with)))
    WHEN 'form'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.forms s
      WHERE ((s.id = (pipeline_stage_history.subject_id)::uuid) AND (s.tenant_id = pipeline_stage_history.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('forms.read'::text) AS tenant_ids_with)))
    WHEN 'document'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.documents s
      WHERE ((s.id = (pipeline_stage_history.subject_id)::uuid) AND (s.tenant_id = pipeline_stage_history.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('documents.read'::text) AS tenant_ids_with)))
    WHEN 'customer'::text THEN ((EXISTS ( SELECT 1
       FROM public.customers s
      WHERE ((s.id = (pipeline_stage_history.subject_id)::uuid) AND (s.organization_id = pipeline_stage_history.tenant_id)))) AND
        ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('customers.read'::text) AS tenant_ids_with)) OR better_supabase.is_subject_member('customer'::text, subject_id)))
    WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.drive_nodes s
      WHERE
        ((s.id = (pipeline_stage_history.subject_id)::uuid) AND (s.tenant_id = pipeline_stage_history.tenant_id) AND (((pipeline_stage_history.tenant_id IN ( SELECT
        better_supabase.tenant_ids_with('drive.read'::text) AS tenant_ids_with)) AND COALESCE(better_supabase.drive_node_readable(s.id), false)) OR
        better_supabase.is_subject_member('drive_node'::text, pipeline_stage_history.subject_id)))))
    WHEN 'organization'::text THEN (EXISTS ( SELECT 1
       FROM public.organizations s
      WHERE ((s.id = (pipeline_stage_history.subject_id)::uuid) AND (s.id = pipeline_stage_history.tenant_id))))
    WHEN 'application'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.applications s
      WHERE ((s.id = (pipeline_stage_history.subject_id)::uuid) AND (s.tenant_id = pipeline_stage_history.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('hiring.read'::text) AS tenant_ids_with)))
    WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
       FROM public.change_requests s
      WHERE ((s.id = (pipeline_stage_history.subject_id)::uuid) AND (s.organization_id = pipeline_stage_history.tenant_id))))
    WHEN 'project'::text THEN (EXISTS ( SELECT 1
       FROM public.projects s
      WHERE ((s.id = (pipeline_stage_history.subject_id)::uuid) AND (s.organization_id = pipeline_stage_history.tenant_id))))
    WHEN 'task'::text THEN (EXISTS ( SELECT 1
       FROM public.tasks s
      WHERE ((s.id = (pipeline_stage_history.subject_id)::uuid) AND (s.organization_id = pipeline_stage_history.tenant_id))))
    ELSE COALESCE(better_supabase.can_subject(subject_type, subject_id, 'read'::text), false)
END));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."pipeline_stage_history"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('pipelines.read'::text) AS tenant_ids_with)) AND
CASE subject_type
    WHEN 'deal'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.deals s
      WHERE ((s.id = (pipeline_stage_history.subject_id)::uuid) AND (s.tenant_id = pipeline_stage_history.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('deals.read'::text) AS tenant_ids_with)))
    WHEN 'work_item'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.work_items s
      WHERE ((s.id = (pipeline_stage_history.subject_id)::uuid) AND (s.tenant_id = pipeline_stage_history.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('tasks.read'::text) AS tenant_ids_with)))
    WHEN 'ledger_account'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.ledger_accounts s
      WHERE ((s.id = (pipeline_stage_history.subject_id)::uuid) AND (s.tenant_id = pipeline_stage_history.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('ledger.read'::text) AS tenant_ids_with)))
    WHEN 'product'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.products s
      WHERE ((s.id = (pipeline_stage_history.subject_id)::uuid) AND (s.tenant_id = pipeline_stage_history.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'product_variant'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.product_variants s
      WHERE ((s.id = (pipeline_stage_history.subject_id)::uuid) AND (s.tenant_id = pipeline_stage_history.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'order'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.orders s
      WHERE ((s.id = (pipeline_stage_history.subject_id)::uuid) AND (s.tenant_id = pipeline_stage_history.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('orders.read'::text) AS tenant_ids_with)))
    WHEN 'calendar_event'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.calendar_events s
      WHERE ((s.id = (pipeline_stage_history.subject_id)::uuid) AND (s.tenant_id = pipeline_stage_history.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('calendar.read'::text) AS tenant_ids_with)))
    WHEN 'booking'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.bookings s
      WHERE ((s.id = (pipeline_stage_history.subject_id)::uuid) AND (s.tenant_id = pipeline_stage_history.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('bookings.read'::text) AS tenant_ids_with)))
    WHEN 'case'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.cases s
      WHERE ((s.id = (pipeline_stage_history.subject_id)::uuid) AND (s.tenant_id = pipeline_stage_history.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('cases.read'::text) AS tenant_ids_with)))
    WHEN 'form'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.forms s
      WHERE ((s.id = (pipeline_stage_history.subject_id)::uuid) AND (s.tenant_id = pipeline_stage_history.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('forms.read'::text) AS tenant_ids_with)))
    WHEN 'document'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.documents s
      WHERE ((s.id = (pipeline_stage_history.subject_id)::uuid) AND (s.tenant_id = pipeline_stage_history.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('documents.read'::text) AS tenant_ids_with)))
    WHEN 'customer'::text THEN ((EXISTS ( SELECT 1
       FROM public.customers s
      WHERE ((s.id = (pipeline_stage_history.subject_id)::uuid) AND (s.organization_id = pipeline_stage_history.tenant_id)))) AND
        ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('customers.read'::text) AS tenant_ids_with)) OR better_supabase.is_subject_member('customer'::text, subject_id)))
    WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.drive_nodes s
      WHERE
        ((s.id = (pipeline_stage_history.subject_id)::uuid) AND (s.tenant_id = pipeline_stage_history.tenant_id) AND (((pipeline_stage_history.tenant_id IN ( SELECT
        better_supabase.tenant_ids_with('drive.read'::text) AS tenant_ids_with)) AND COALESCE(better_supabase.drive_node_readable(s.id), false)) OR
        better_supabase.is_subject_member('drive_node'::text, pipeline_stage_history.subject_id)))))
    WHEN 'organization'::text THEN (EXISTS ( SELECT 1
       FROM public.organizations s
      WHERE ((s.id = (pipeline_stage_history.subject_id)::uuid) AND (s.id = pipeline_stage_history.tenant_id))))
    WHEN 'application'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.applications s
      WHERE ((s.id = (pipeline_stage_history.subject_id)::uuid) AND (s.tenant_id = pipeline_stage_history.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('hiring.read'::text) AS tenant_ids_with)))
    WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
       FROM public.change_requests s
      WHERE ((s.id = (pipeline_stage_history.subject_id)::uuid) AND (s.organization_id = pipeline_stage_history.tenant_id))))
    WHEN 'project'::text THEN (EXISTS ( SELECT 1
       FROM public.projects s
      WHERE ((s.id = (pipeline_stage_history.subject_id)::uuid) AND (s.organization_id = pipeline_stage_history.tenant_id))))
    WHEN 'task'::text THEN (EXISTS ( SELECT 1
       FROM public.tasks s
      WHERE ((s.id = (pipeline_stage_history.subject_id)::uuid) AND (s.organization_id = pipeline_stage_history.tenant_id))))
    ELSE COALESCE(better_supabase.can_subject(subject_type, subject_id, 'read'::text), false)
END)));

CREATE POLICY "bsb_sla_clocks_read" ON "better_supabase"."sla_clocks"
  FOR SELECT
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.tenant_ids_with('sla.read'::text) AS tenant_ids_with)) AND
CASE subject_type
    WHEN 'company'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.companies s
      WHERE ((s.id = (sla_clocks.subject_id)::uuid) AND (s.tenant_id = sla_clocks.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contacts.read'::text) AS tenant_ids_with)))
    WHEN 'person'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.people s
      WHERE ((s.id = (sla_clocks.subject_id)::uuid) AND (s.tenant_id = sla_clocks.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contacts.read'::text) AS tenant_ids_with)))
    WHEN 'deal'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.deals s
      WHERE ((s.id = (sla_clocks.subject_id)::uuid) AND (s.tenant_id = sla_clocks.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('deals.read'::text) AS tenant_ids_with)))
    WHEN 'activity'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.activities s
      WHERE ((s.id = (sla_clocks.subject_id)::uuid) AND (s.tenant_id = sla_clocks.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('activities.read'::text) AS tenant_ids_with)))
    WHEN 'quote'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.quotes s
      WHERE ((s.id = (sla_clocks.subject_id)::uuid) AND (s.tenant_id = sla_clocks.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('quotes.read'::text) AS tenant_ids_with)))
    WHEN 'work_item'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.work_items s
      WHERE ((s.id = (sla_clocks.subject_id)::uuid) AND (s.tenant_id = sla_clocks.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('tasks.read'::text) AS tenant_ids_with)))
    WHEN 'invoice'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.invoices s
      WHERE ((s.id = (sla_clocks.subject_id)::uuid) AND (s.tenant_id = sla_clocks.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('invoices.read'::text) AS tenant_ids_with)))
    WHEN 'ledger_account'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.ledger_accounts s
      WHERE ((s.id = (sla_clocks.subject_id)::uuid) AND (s.tenant_id = sla_clocks.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('ledger.read'::text) AS tenant_ids_with)))
    WHEN 'product'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.products s
      WHERE ((s.id = (sla_clocks.subject_id)::uuid) AND (s.tenant_id = sla_clocks.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'product_variant'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.product_variants s
      WHERE ((s.id = (sla_clocks.subject_id)::uuid) AND (s.tenant_id = sla_clocks.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'order'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.orders s
      WHERE ((s.id = (sla_clocks.subject_id)::uuid) AND (s.tenant_id = sla_clocks.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('orders.read'::text) AS tenant_ids_with)))
    WHEN 'calendar_event'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.calendar_events s
      WHERE ((s.id = (sla_clocks.subject_id)::uuid) AND (s.tenant_id = sla_clocks.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('calendar.read'::text) AS tenant_ids_with)))
    WHEN 'booking'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.bookings s
      WHERE ((s.id = (sla_clocks.subject_id)::uuid) AND (s.tenant_id = sla_clocks.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('bookings.read'::text) AS tenant_ids_with)))
    WHEN 'case'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.cases s
      WHERE ((s.id = (sla_clocks.subject_id)::uuid) AND (s.tenant_id = sla_clocks.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('cases.read'::text) AS tenant_ids_with)))
    WHEN 'form'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.forms s
      WHERE ((s.id = (sla_clocks.subject_id)::uuid) AND (s.tenant_id = sla_clocks.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('forms.read'::text) AS tenant_ids_with)))
    WHEN 'document'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.documents s
      WHERE ((s.id = (sla_clocks.subject_id)::uuid) AND (s.tenant_id = sla_clocks.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('documents.read'::text) AS tenant_ids_with)))
    WHEN 'customer'::text THEN ((EXISTS ( SELECT 1
       FROM public.customers s
      WHERE ((s.id = (sla_clocks.subject_id)::uuid) AND (s.organization_id = sla_clocks.tenant_id)))) AND
        ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('customers.read'::text) AS tenant_ids_with)) OR better_supabase.is_subject_member('customer'::text, subject_id)))
    WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.drive_nodes s
      WHERE
        ((s.id = (sla_clocks.subject_id)::uuid) AND (s.tenant_id = sla_clocks.tenant_id) AND (((sla_clocks.tenant_id IN ( SELECT better_supabase.tenant_ids_with('drive.read'::text)
        AS tenant_ids_with)) AND COALESCE(better_supabase.drive_node_readable(s.id), false)) OR better_supabase.is_subject_member('drive_node'::text, sla_clocks.subject_id)))))
    WHEN 'organization'::text THEN (EXISTS ( SELECT 1
       FROM public.organizations s
      WHERE ((s.id = (sla_clocks.subject_id)::uuid) AND (s.id = sla_clocks.tenant_id))))
    WHEN 'application'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.applications s
      WHERE ((s.id = (sla_clocks.subject_id)::uuid) AND (s.tenant_id = sla_clocks.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('hiring.read'::text) AS tenant_ids_with)))
    WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
       FROM public.change_requests s
      WHERE ((s.id = (sla_clocks.subject_id)::uuid) AND (s.organization_id = sla_clocks.tenant_id))))
    WHEN 'project'::text THEN (EXISTS ( SELECT 1
       FROM public.projects s
      WHERE ((s.id = (sla_clocks.subject_id)::uuid) AND (s.organization_id = sla_clocks.tenant_id))))
    WHEN 'task'::text THEN (EXISTS ( SELECT 1
       FROM public.tasks s
      WHERE ((s.id = (sla_clocks.subject_id)::uuid) AND (s.organization_id = sla_clocks.tenant_id))))
    ELSE COALESCE(better_supabase.can_subject(subject_type, subject_id, 'read'::text), false)
END));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."sla_clocks"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('sla.read'::text) AS
    tenant_ids_with)) AND
CASE subject_type
    WHEN 'company'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.companies s
      WHERE ((s.id = (sla_clocks.subject_id)::uuid) AND (s.tenant_id = sla_clocks.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contacts.read'::text) AS tenant_ids_with)))
    WHEN 'person'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.people s
      WHERE ((s.id = (sla_clocks.subject_id)::uuid) AND (s.tenant_id = sla_clocks.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contacts.read'::text) AS tenant_ids_with)))
    WHEN 'deal'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.deals s
      WHERE ((s.id = (sla_clocks.subject_id)::uuid) AND (s.tenant_id = sla_clocks.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('deals.read'::text) AS tenant_ids_with)))
    WHEN 'activity'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.activities s
      WHERE ((s.id = (sla_clocks.subject_id)::uuid) AND (s.tenant_id = sla_clocks.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('activities.read'::text) AS tenant_ids_with)))
    WHEN 'quote'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.quotes s
      WHERE ((s.id = (sla_clocks.subject_id)::uuid) AND (s.tenant_id = sla_clocks.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('quotes.read'::text) AS tenant_ids_with)))
    WHEN 'work_item'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.work_items s
      WHERE ((s.id = (sla_clocks.subject_id)::uuid) AND (s.tenant_id = sla_clocks.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('tasks.read'::text) AS tenant_ids_with)))
    WHEN 'invoice'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.invoices s
      WHERE ((s.id = (sla_clocks.subject_id)::uuid) AND (s.tenant_id = sla_clocks.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('invoices.read'::text) AS tenant_ids_with)))
    WHEN 'ledger_account'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.ledger_accounts s
      WHERE ((s.id = (sla_clocks.subject_id)::uuid) AND (s.tenant_id = sla_clocks.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('ledger.read'::text) AS tenant_ids_with)))
    WHEN 'product'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.products s
      WHERE ((s.id = (sla_clocks.subject_id)::uuid) AND (s.tenant_id = sla_clocks.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'product_variant'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.product_variants s
      WHERE ((s.id = (sla_clocks.subject_id)::uuid) AND (s.tenant_id = sla_clocks.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'order'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.orders s
      WHERE ((s.id = (sla_clocks.subject_id)::uuid) AND (s.tenant_id = sla_clocks.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('orders.read'::text) AS tenant_ids_with)))
    WHEN 'calendar_event'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.calendar_events s
      WHERE ((s.id = (sla_clocks.subject_id)::uuid) AND (s.tenant_id = sla_clocks.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('calendar.read'::text) AS tenant_ids_with)))
    WHEN 'booking'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.bookings s
      WHERE ((s.id = (sla_clocks.subject_id)::uuid) AND (s.tenant_id = sla_clocks.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('bookings.read'::text) AS tenant_ids_with)))
    WHEN 'case'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.cases s
      WHERE ((s.id = (sla_clocks.subject_id)::uuid) AND (s.tenant_id = sla_clocks.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('cases.read'::text) AS tenant_ids_with)))
    WHEN 'form'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.forms s
      WHERE ((s.id = (sla_clocks.subject_id)::uuid) AND (s.tenant_id = sla_clocks.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('forms.read'::text) AS tenant_ids_with)))
    WHEN 'document'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.documents s
      WHERE ((s.id = (sla_clocks.subject_id)::uuid) AND (s.tenant_id = sla_clocks.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('documents.read'::text) AS tenant_ids_with)))
    WHEN 'customer'::text THEN ((EXISTS ( SELECT 1
       FROM public.customers s
      WHERE ((s.id = (sla_clocks.subject_id)::uuid) AND (s.organization_id = sla_clocks.tenant_id)))) AND
        ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('customers.read'::text) AS tenant_ids_with)) OR better_supabase.is_subject_member('customer'::text, subject_id)))
    WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.drive_nodes s
      WHERE
        ((s.id = (sla_clocks.subject_id)::uuid) AND (s.tenant_id = sla_clocks.tenant_id) AND (((sla_clocks.tenant_id IN ( SELECT better_supabase.tenant_ids_with('drive.read'::text)
        AS tenant_ids_with)) AND COALESCE(better_supabase.drive_node_readable(s.id), false)) OR better_supabase.is_subject_member('drive_node'::text, sla_clocks.subject_id)))))
    WHEN 'organization'::text THEN (EXISTS ( SELECT 1
       FROM public.organizations s
      WHERE ((s.id = (sla_clocks.subject_id)::uuid) AND (s.id = sla_clocks.tenant_id))))
    WHEN 'application'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.applications s
      WHERE ((s.id = (sla_clocks.subject_id)::uuid) AND (s.tenant_id = sla_clocks.tenant_id)))) AND
        (tenant_id IN ( SELECT better_supabase.tenant_ids_with('hiring.read'::text) AS tenant_ids_with)))
    WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
       FROM public.change_requests s
      WHERE ((s.id = (sla_clocks.subject_id)::uuid) AND (s.organization_id = sla_clocks.tenant_id))))
    WHEN 'project'::text THEN (EXISTS ( SELECT 1
       FROM public.projects s
      WHERE ((s.id = (sla_clocks.subject_id)::uuid) AND (s.organization_id = sla_clocks.tenant_id))))
    WHEN 'task'::text THEN (EXISTS ( SELECT 1
       FROM public.tasks s
      WHERE ((s.id = (sla_clocks.subject_id)::uuid) AND (s.organization_id = sla_clocks.tenant_id))))
    ELSE COALESCE(better_supabase.can_subject(subject_type, subject_id, 'read'::text), false)
END)));

REVOKE ALL ON FUNCTION "api"."get_company"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_company"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_person"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_person"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_company"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_company"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_person"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_person"(uuid) TO "authenticated", "service_role";
