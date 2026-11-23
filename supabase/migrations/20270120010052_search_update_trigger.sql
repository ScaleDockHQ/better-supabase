DROP TRIGGER "bsb_search_activity_index" ON "better_supabase"."activities";

DROP TRIGGER "bsb_search_advisory_index" ON "better_supabase"."advisories";

DROP TRIGGER "bsb_search_advisory_product_index" ON "better_supabase"."advisory_products";

DROP TRIGGER "bsb_search_asset_location_index" ON "better_supabase"."asset_locations";

DROP TRIGGER "bsb_search_asset_index" ON "better_supabase"."assets";

DROP TRIGGER "bsb_search_bank_account_index" ON "better_supabase"."bank_accounts";

DROP TRIGGER "bsb_search_booking_index" ON "better_supabase"."bookings";

DROP TRIGGER "bsb_search_calendar_event_index" ON "better_supabase"."calendar_events";

DROP TRIGGER "bsb_search_care_plan_index" ON "better_supabase"."care_plans";

DROP TRIGGER "bsb_search_case_index" ON "better_supabase"."cases";

DROP TRIGGER "bsb_search_channel_index" ON "better_supabase"."channels";

DROP TRIGGER "bsb_search_company_index" ON "better_supabase"."companies";

DROP TRIGGER "bsb_search_compliance_policy_index" ON "better_supabase"."compliance_policies";

DROP TRIGGER "bsb_search_content_entry_index" ON "better_supabase"."content_entries";

DROP TRIGGER "bsb_search_contract_index" ON "better_supabase"."contracts";

DROP TRIGGER "bsb_search_control_index" ON "better_supabase"."controls";

DROP TRIGGER "bsb_search_conversation_index" ON "better_supabase"."conversations";

DROP TRIGGER "bsb_search_course_index" ON "better_supabase"."courses";

DROP TRIGGER "bsb_search_dam_usage_right_index" ON "better_supabase"."dam_usage_rights";

DROP TRIGGER "bsb_search_deal_index" ON "better_supabase"."deals";

DROP TRIGGER "bsb_search_document_index" ON "better_supabase"."documents";

DROP TRIGGER "bsb_search_donation_fund_index" ON "better_supabase"."donation_funds";

DROP TRIGGER "bsb_search_drive_node_index" ON "better_supabase"."drive_nodes";

DROP TRIGGER "bsb_search_employee_index" ON "better_supabase"."employees";

DROP TRIGGER "bsb_search_expense_line_index" ON "better_supabase"."expense_lines";

DROP TRIGGER "bsb_search_expense_report_index" ON "better_supabase"."expense_reports";

DROP TRIGGER "bsb_search_form_index" ON "better_supabase"."forms";

DROP TRIGGER "bsb_search_incident_index" ON "better_supabase"."incidents";

DROP TRIGGER "bsb_search_inspection_finding_index" ON "better_supabase"."inspection_findings";

DROP TRIGGER "bsb_search_inspection_program_index" ON "better_supabase"."inspection_programs";

DROP TRIGGER "bsb_search_inspection_index" ON "better_supabase"."inspections";

DROP TRIGGER "bsb_search_invoice_index" ON "better_supabase"."invoices";

DROP TRIGGER "bsb_search_lease_index" ON "better_supabase"."leases";

DROP TRIGGER "bsb_search_ledger_account_index" ON "better_supabase"."ledger_accounts";

DROP TRIGGER "bsb_search_lims_sample_index" ON "better_supabase"."lims_samples";

DROP TRIGGER "bsb_search_maintenance_plan_index" ON "better_supabase"."maintenance_plans";

DROP TRIGGER "bsb_search_meeting_decision_index" ON "better_supabase"."meeting_decisions";

DROP TRIGGER "bsb_search_meeting_index" ON "better_supabase"."meetings";

DROP TRIGGER "bsb_search_message_index" ON "better_supabase"."messages";

DROP TRIGGER "bsb_search_order_index" ON "better_supabase"."orders";

DROP TRIGGER "bsb_search_person_index" ON "better_supabase"."people";

DROP TRIGGER "bsb_search_post_index" ON "better_supabase"."posts";

DROP TRIGGER "bsb_search_product_variant_index" ON "better_supabase"."product_variants";

DROP TRIGGER "bsb_search_production_order_index" ON "better_supabase"."production_orders";

DROP TRIGGER "bsb_search_product_index" ON "better_supabase"."products";

DROP TRIGGER "bsb_search_qualification_type_index" ON "better_supabase"."qualification_types";

DROP TRIGGER "bsb_search_quote_index" ON "better_supabase"."quotes";

DROP TRIGGER "bsb_search_rfq_index" ON "better_supabase"."rfqs";

DROP TRIGGER "bsb_search_risk_index" ON "better_supabase"."risks";

DROP TRIGGER "bsb_search_shipment_index" ON "better_supabase"."shipments";

DROP TRIGGER "bsb_search_tax_code_index" ON "better_supabase"."tax_codes";

DROP TRIGGER "bsb_search_till_index" ON "better_supabase"."tills";

DROP TRIGGER "bsb_search_vulnerability_index" ON "better_supabase"."vulnerabilities";

DROP TRIGGER "bsb_search_warranty_claim_index" ON "better_supabase"."warranty_claims";

DROP TRIGGER "bsb_search_work_center_index" ON "better_supabase"."work_centers";

DROP TRIGGER "bsb_search_work_item_index" ON "better_supabase"."work_items";

DROP TRIGGER "bsb_search_work_order_index" ON "better_supabase"."work_orders";

DROP TRIGGER "bsb_search_task_index" ON "public"."tasks";

CREATE TRIGGER bsb_search_activity_index_u
  AFTER UPDATE OF id, tenant_id, title, body, outcome, archived_at ON better_supabase.activities
  FOR EACH ROW
  WHEN
    (((old.id IS DISTINCT FROM new.id) OR (old.tenant_id IS DISTINCT FROM new.tenant_id) OR (old.title IS DISTINCT FROM new.title) OR (old.body IS DISTINCT FROM new.body) OR
    (old.outcome IS DISTINCT FROM new.outcome) OR (old.archived_at IS DISTINCT FROM new.archived_at)))
  EXECUTE FUNCTION better_supabase.search_index_row('activity', 'id');

CREATE TRIGGER bsb_search_activity_index
  AFTER INSERT OR DELETE ON better_supabase.activities
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('activity', 'id');

CREATE TRIGGER bsb_search_advisory_index_u
  AFTER UPDATE OF id, tenant_id, title, tracking_id, summary ON better_supabase.advisories
  FOR EACH ROW
  WHEN
    (((old.id IS DISTINCT FROM new.id) OR (old.tenant_id IS DISTINCT FROM new.tenant_id) OR (old.title IS DISTINCT FROM new.title) OR (old.tracking_id IS DISTINCT FROM
    new.tracking_id) OR (old.summary IS DISTINCT FROM new.summary)))
  EXECUTE FUNCTION better_supabase.search_index_row('advisory', 'id');

CREATE TRIGGER bsb_search_advisory_index
  AFTER INSERT OR DELETE ON better_supabase.advisories
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('advisory', 'id');

CREATE TRIGGER bsb_search_advisory_product_index_u
  AFTER UPDATE OF id, tenant_id, name, archived_at ON better_supabase.advisory_products
  FOR EACH ROW
  WHEN
    (((old.id IS DISTINCT FROM new.id) OR (old.tenant_id IS DISTINCT FROM new.tenant_id) OR (old.name IS DISTINCT FROM new.name) OR (old.archived_at IS DISTINCT FROM
    new.archived_at)))
  EXECUTE FUNCTION better_supabase.search_index_row('advisory_product', 'id');

CREATE TRIGGER bsb_search_advisory_product_index
  AFTER INSERT OR DELETE ON better_supabase.advisory_products
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('advisory_product', 'id');

CREATE TRIGGER bsb_search_asset_location_index_u
  AFTER UPDATE OF id, tenant_id, name ON better_supabase.asset_locations
  FOR EACH ROW
  WHEN (((old.id IS DISTINCT FROM new.id) OR (old.tenant_id IS DISTINCT FROM new.tenant_id) OR (old.name IS DISTINCT FROM new.name)))
  EXECUTE FUNCTION better_supabase.search_index_row('asset_location', 'id');

CREATE TRIGGER bsb_search_asset_location_index
  AFTER INSERT OR DELETE ON better_supabase.asset_locations
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('asset_location', 'id');

CREATE TRIGGER bsb_search_asset_index_u
  AFTER UPDATE OF id, tenant_id, name ON better_supabase.assets
  FOR EACH ROW
  WHEN (((old.id IS DISTINCT FROM new.id) OR (old.tenant_id IS DISTINCT FROM new.tenant_id) OR (old.name IS DISTINCT FROM new.name)))
  EXECUTE FUNCTION better_supabase.search_index_row('asset', 'id');

CREATE TRIGGER bsb_search_asset_index
  AFTER INSERT OR DELETE ON better_supabase.assets
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('asset', 'id');

CREATE TRIGGER bsb_search_bank_account_index_u
  AFTER UPDATE OF id, tenant_id, name, iban, holder, archived_at ON better_supabase.bank_accounts
  FOR EACH ROW
  WHEN
    (((old.id IS DISTINCT FROM new.id) OR (old.tenant_id IS DISTINCT FROM new.tenant_id) OR (old.name IS DISTINCT FROM new.name) OR (old.iban IS DISTINCT FROM new.iban) OR
    (old.holder IS DISTINCT FROM new.holder) OR (old.archived_at IS DISTINCT FROM new.archived_at)))
  EXECUTE FUNCTION better_supabase.search_index_row('bank_account', 'id');

CREATE TRIGGER bsb_search_bank_account_index
  AFTER INSERT OR DELETE ON better_supabase.bank_accounts
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('bank_account', 'id');

CREATE TRIGGER bsb_search_booking_index_u
  AFTER UPDATE OF id, tenant_id, customer_name ON better_supabase.bookings
  FOR EACH ROW
  WHEN (((old.id IS DISTINCT FROM new.id) OR (old.tenant_id IS DISTINCT FROM new.tenant_id) OR (old.customer_name IS DISTINCT FROM new.customer_name)))
  EXECUTE FUNCTION better_supabase.search_index_row('booking', 'id');

CREATE TRIGGER bsb_search_booking_index
  AFTER INSERT OR DELETE ON better_supabase.bookings
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('booking', 'id');

CREATE TRIGGER bsb_search_calendar_event_index_u
  AFTER UPDATE OF id, tenant_id, title, description, location ON better_supabase.calendar_events
  FOR EACH ROW
  WHEN
    (((old.id IS DISTINCT FROM new.id) OR (old.tenant_id IS DISTINCT FROM new.tenant_id) OR (old.title IS DISTINCT FROM new.title) OR (old.description IS DISTINCT FROM
    new.description) OR (old.location IS DISTINCT FROM new.location)))
  EXECUTE FUNCTION better_supabase.search_index_row('calendar_event', 'id');

CREATE TRIGGER bsb_search_calendar_event_index
  AFTER INSERT OR DELETE ON better_supabase.calendar_events
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('calendar_event', 'id');

CREATE TRIGGER bsb_search_care_plan_index_u
  AFTER UPDATE OF id, tenant_id, title ON better_supabase.care_plans
  FOR EACH ROW
  WHEN (((old.id IS DISTINCT FROM new.id) OR (old.tenant_id IS DISTINCT FROM new.tenant_id) OR (old.title IS DISTINCT FROM new.title)))
  EXECUTE FUNCTION better_supabase.search_index_row('care_plan', 'id');

CREATE TRIGGER bsb_search_care_plan_index
  AFTER INSERT OR DELETE ON better_supabase.care_plans
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('care_plan', 'id');

CREATE TRIGGER bsb_search_case_index_u
  AFTER UPDATE OF id, tenant_id, title, number, description, root_cause, archived_at ON better_supabase.cases
  FOR EACH ROW
  WHEN
    (((old.id IS DISTINCT FROM new.id) OR (old.tenant_id IS DISTINCT FROM new.tenant_id) OR (old.title IS DISTINCT FROM new.title) OR (old.number IS DISTINCT FROM new.number) OR
    (old.description IS DISTINCT FROM new.description) OR (old.root_cause IS DISTINCT FROM new.root_cause) OR (old.archived_at IS DISTINCT FROM new.archived_at)))
  EXECUTE FUNCTION better_supabase.search_index_row('case', 'id');

CREATE TRIGGER bsb_search_case_index
  AFTER INSERT OR DELETE ON better_supabase.cases
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('case', 'id');

CREATE TRIGGER bsb_search_channel_index_u
  AFTER UPDATE OF id, tenant_id, name, topic, purpose ON better_supabase.channels
  FOR EACH ROW
  WHEN
    (((old.id IS DISTINCT FROM new.id) OR (old.tenant_id IS DISTINCT FROM new.tenant_id) OR (old.name IS DISTINCT FROM new.name) OR (old.topic IS DISTINCT FROM new.topic) OR
    (old.purpose IS DISTINCT FROM new.purpose)))
  EXECUTE FUNCTION better_supabase.search_index_row('channel', 'id');

CREATE TRIGGER bsb_search_channel_index
  AFTER INSERT OR DELETE ON better_supabase.channels
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('channel', 'id');

CREATE TRIGGER bsb_search_company_index_u
  AFTER UPDATE OF id, tenant_id, name, DOMAIN, website ON better_supabase.companies
  FOR EACH ROW
  WHEN
    (((old.id IS DISTINCT FROM new.id) OR (old.tenant_id IS DISTINCT FROM new.tenant_id) OR (old.name IS DISTINCT FROM new.name) OR (old.domain IS DISTINCT FROM new.domain) OR
    (old.website IS DISTINCT FROM new.website)))
  EXECUTE FUNCTION better_supabase.search_index_row('company', 'id');

CREATE TRIGGER bsb_search_company_index
  AFTER INSERT OR DELETE ON better_supabase.companies
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('company', 'id');

CREATE TRIGGER bsb_search_compliance_policy_index_u
  AFTER UPDATE OF id, tenant_id, title, key ON better_supabase.compliance_policies
  FOR EACH ROW
  WHEN (((old.id IS DISTINCT FROM new.id) OR (old.tenant_id IS DISTINCT FROM new.tenant_id) OR (old.title IS DISTINCT FROM new.title) OR (old.key IS DISTINCT FROM new.key)))
  EXECUTE FUNCTION better_supabase.search_index_row('compliance_policy', 'id');

CREATE TRIGGER bsb_search_compliance_policy_index
  AFTER INSERT OR DELETE ON better_supabase.compliance_policies
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('compliance_policy', 'id');

CREATE TRIGGER bsb_search_content_entry_index_u
  AFTER UPDATE OF id, tenant_id, title, summary ON better_supabase.content_entries
  FOR EACH ROW
  WHEN
    (((old.id IS DISTINCT FROM new.id) OR (old.tenant_id IS DISTINCT FROM new.tenant_id) OR (old.title IS DISTINCT FROM new.title) OR (old.summary IS DISTINCT FROM new.summary)))
  EXECUTE FUNCTION better_supabase.search_index_row('content_entry', 'id');

CREATE TRIGGER bsb_search_content_entry_index
  AFTER INSERT OR DELETE ON better_supabase.content_entries
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('content_entry', 'id');

CREATE TRIGGER bsb_search_contract_index_u
  AFTER UPDATE OF id, tenant_id, title ON better_supabase.contracts
  FOR EACH ROW
  WHEN (((old.id IS DISTINCT FROM new.id) OR (old.tenant_id IS DISTINCT FROM new.tenant_id) OR (old.title IS DISTINCT FROM new.title)))
  EXECUTE FUNCTION better_supabase.search_index_row('contract', 'id');

CREATE TRIGGER bsb_search_contract_index
  AFTER INSERT OR DELETE ON better_supabase.contracts
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('contract', 'id');

CREATE TRIGGER bsb_search_control_index_u
  AFTER UPDATE OF id, tenant_id, title ON better_supabase.controls
  FOR EACH ROW
  WHEN (((old.id IS DISTINCT FROM new.id) OR (old.tenant_id IS DISTINCT FROM new.tenant_id) OR (old.title IS DISTINCT FROM new.title)))
  EXECUTE FUNCTION better_supabase.search_index_row('control', 'id');

CREATE TRIGGER bsb_search_control_index
  AFTER INSERT OR DELETE ON better_supabase.controls
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('control', 'id');

CREATE TRIGGER bsb_search_conversation_index_u
  AFTER UPDATE OF id, tenant_id, title, archived_at ON better_supabase.conversations
  FOR EACH ROW
  WHEN
    (((old.id IS DISTINCT FROM new.id) OR (old.tenant_id IS DISTINCT FROM new.tenant_id) OR (old.title IS DISTINCT FROM new.title) OR (old.archived_at IS DISTINCT FROM
    new.archived_at)))
  EXECUTE FUNCTION better_supabase.search_index_row('conversation', 'id');

CREATE TRIGGER bsb_search_conversation_index
  AFTER INSERT OR DELETE ON better_supabase.conversations
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('conversation', 'id');

CREATE TRIGGER bsb_search_course_index_u
  AFTER UPDATE OF id, tenant_id, title, summary ON better_supabase.courses
  FOR EACH ROW
  WHEN
    (((old.id IS DISTINCT FROM new.id) OR (old.tenant_id IS DISTINCT FROM new.tenant_id) OR (old.title IS DISTINCT FROM new.title) OR (old.summary IS DISTINCT FROM new.summary)))
  EXECUTE FUNCTION better_supabase.search_index_row('course', 'id');

CREATE TRIGGER bsb_search_course_index
  AFTER INSERT OR DELETE ON better_supabase.courses
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('course', 'id');

CREATE TRIGGER bsb_search_dam_usage_right_index_u
  AFTER UPDATE OF id, tenant_id, licensee ON better_supabase.dam_usage_rights
  FOR EACH ROW
  WHEN (((old.id IS DISTINCT FROM new.id) OR (old.tenant_id IS DISTINCT FROM new.tenant_id) OR (old.licensee IS DISTINCT FROM new.licensee)))
  EXECUTE FUNCTION better_supabase.search_index_row('dam_usage_right', 'id');

CREATE TRIGGER bsb_search_dam_usage_right_index
  AFTER INSERT OR DELETE ON better_supabase.dam_usage_rights
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('dam_usage_right', 'id');

CREATE TRIGGER bsb_search_deal_index_u
  AFTER UPDATE OF id, tenant_id, name, identifier, note, archived_at ON better_supabase.deals
  FOR EACH ROW
  WHEN
    (((old.id IS DISTINCT FROM new.id) OR (old.tenant_id IS DISTINCT FROM new.tenant_id) OR (old.name IS DISTINCT FROM new.name) OR (old.identifier IS DISTINCT FROM new.identifier)
    OR (old.note IS DISTINCT FROM new.note) OR (old.archived_at IS DISTINCT FROM new.archived_at)))
  EXECUTE FUNCTION better_supabase.search_index_row('deal', 'id');

CREATE TRIGGER bsb_search_deal_index
  AFTER INSERT OR DELETE ON better_supabase.deals
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('deal', 'id');

CREATE TRIGGER bsb_search_document_index_u
  AFTER UPDATE OF id, tenant_id, name ON better_supabase.documents
  FOR EACH ROW
  WHEN (((old.id IS DISTINCT FROM new.id) OR (old.tenant_id IS DISTINCT FROM new.tenant_id) OR (old.name IS DISTINCT FROM new.name)))
  EXECUTE FUNCTION better_supabase.search_index_row('document', 'id');

CREATE TRIGGER bsb_search_document_index
  AFTER INSERT OR DELETE ON better_supabase.documents
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('document', 'id');

CREATE TRIGGER bsb_search_donation_fund_index_u
  AFTER UPDATE OF id, tenant_id, name ON better_supabase.donation_funds
  FOR EACH ROW
  WHEN (((old.id IS DISTINCT FROM new.id) OR (old.tenant_id IS DISTINCT FROM new.tenant_id) OR (old.name IS DISTINCT FROM new.name)))
  EXECUTE FUNCTION better_supabase.search_index_row('donation_fund', 'id');

CREATE TRIGGER bsb_search_donation_fund_index
  AFTER INSERT OR DELETE ON better_supabase.donation_funds
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('donation_fund', 'id');

CREATE TRIGGER bsb_search_drive_node_index_u
  AFTER UPDATE OF id, tenant_id, name, archived_at ON better_supabase.drive_nodes
  FOR EACH ROW
  WHEN
    (((old.id IS DISTINCT FROM new.id) OR (old.tenant_id IS DISTINCT FROM new.tenant_id) OR (old.name IS DISTINCT FROM new.name) OR (old.archived_at IS DISTINCT FROM
    new.archived_at)))
  EXECUTE FUNCTION better_supabase.search_index_row('drive_node', 'id');

CREATE TRIGGER bsb_search_drive_node_index
  AFTER INSERT OR DELETE ON better_supabase.drive_nodes
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('drive_node', 'id');

CREATE TRIGGER bsb_search_employee_index_u
  AFTER UPDATE OF id, tenant_id, name, email, job_title ON better_supabase.employees
  FOR EACH ROW
  WHEN
    (((old.id IS DISTINCT FROM new.id) OR (old.tenant_id IS DISTINCT FROM new.tenant_id) OR (old.name IS DISTINCT FROM new.name) OR (old.email IS DISTINCT FROM new.email) OR
    (old.job_title IS DISTINCT FROM new.job_title)))
  EXECUTE FUNCTION better_supabase.search_index_row('employee', 'id');

CREATE TRIGGER bsb_search_employee_index
  AFTER INSERT OR DELETE ON better_supabase.employees
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('employee', 'id');

CREATE TRIGGER bsb_search_expense_line_index_u
  AFTER UPDATE OF id, tenant_id, description ON better_supabase.expense_lines
  FOR EACH ROW
  WHEN (((old.id IS DISTINCT FROM new.id) OR (old.tenant_id IS DISTINCT FROM new.tenant_id) OR (old.description IS DISTINCT FROM new.description)))
  EXECUTE FUNCTION better_supabase.search_index_row('expense_line', 'id');

CREATE TRIGGER bsb_search_expense_line_index
  AFTER INSERT OR DELETE ON better_supabase.expense_lines
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('expense_line', 'id');

CREATE TRIGGER bsb_search_expense_report_index_u
  AFTER UPDATE OF id, tenant_id, title ON better_supabase.expense_reports
  FOR EACH ROW
  WHEN (((old.id IS DISTINCT FROM new.id) OR (old.tenant_id IS DISTINCT FROM new.tenant_id) OR (old.title IS DISTINCT FROM new.title)))
  EXECUTE FUNCTION better_supabase.search_index_row('expense_report', 'id');

CREATE TRIGGER bsb_search_expense_report_index
  AFTER INSERT OR DELETE ON better_supabase.expense_reports
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('expense_report', 'id');

CREATE TRIGGER bsb_search_form_index_u
  AFTER UPDATE OF id, tenant_id, title ON better_supabase.forms
  FOR EACH ROW
  WHEN (((old.id IS DISTINCT FROM new.id) OR (old.tenant_id IS DISTINCT FROM new.tenant_id) OR (old.title IS DISTINCT FROM new.title)))
  EXECUTE FUNCTION better_supabase.search_index_row('form', 'id');

CREATE TRIGGER bsb_search_form_index
  AFTER INSERT OR DELETE ON better_supabase.forms
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('form', 'id');

CREATE TRIGGER bsb_search_incident_index_u
  AFTER UPDATE OF id, tenant_id, title ON better_supabase.incidents
  FOR EACH ROW
  WHEN (((old.id IS DISTINCT FROM new.id) OR (old.tenant_id IS DISTINCT FROM new.tenant_id) OR (old.title IS DISTINCT FROM new.title)))
  EXECUTE FUNCTION better_supabase.search_index_row('incident', 'id');

CREATE TRIGGER bsb_search_incident_index
  AFTER INSERT OR DELETE ON better_supabase.incidents
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('incident', 'id');

CREATE TRIGGER bsb_search_inspection_finding_index_u
  AFTER UPDATE OF id, tenant_id, title ON better_supabase.inspection_findings
  FOR EACH ROW
  WHEN (((old.id IS DISTINCT FROM new.id) OR (old.tenant_id IS DISTINCT FROM new.tenant_id) OR (old.title IS DISTINCT FROM new.title)))
  EXECUTE FUNCTION better_supabase.search_index_row('inspection_finding', 'id');

CREATE TRIGGER bsb_search_inspection_finding_index
  AFTER INSERT OR DELETE ON better_supabase.inspection_findings
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('inspection_finding', 'id');

CREATE TRIGGER bsb_search_inspection_program_index_u
  AFTER UPDATE OF id, tenant_id, name, archived_at ON better_supabase.inspection_programs
  FOR EACH ROW
  WHEN
    (((old.id IS DISTINCT FROM new.id) OR (old.tenant_id IS DISTINCT FROM new.tenant_id) OR (old.name IS DISTINCT FROM new.name) OR (old.archived_at IS DISTINCT FROM
    new.archived_at)))
  EXECUTE FUNCTION better_supabase.search_index_row('inspection_program', 'id');

CREATE TRIGGER bsb_search_inspection_program_index
  AFTER INSERT OR DELETE ON better_supabase.inspection_programs
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('inspection_program', 'id');

CREATE TRIGGER bsb_search_inspection_index_u
  AFTER UPDATE OF id, tenant_id, title, number, scope, summary ON better_supabase.inspections
  FOR EACH ROW
  WHEN
    (((old.id IS DISTINCT FROM new.id) OR (old.tenant_id IS DISTINCT FROM new.tenant_id) OR (old.title IS DISTINCT FROM new.title) OR (old.number IS DISTINCT FROM new.number) OR
    (old.scope IS DISTINCT FROM new.scope) OR (old.summary IS DISTINCT FROM new.summary)))
  EXECUTE FUNCTION better_supabase.search_index_row('inspection', 'id');

CREATE TRIGGER bsb_search_inspection_index
  AFTER INSERT OR DELETE ON better_supabase.inspections
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('inspection', 'id');

CREATE TRIGGER bsb_search_invoice_index_u
  AFTER UPDATE OF id, tenant_id, title ON better_supabase.invoices
  FOR EACH ROW
  WHEN (((old.id IS DISTINCT FROM new.id) OR (old.tenant_id IS DISTINCT FROM new.tenant_id) OR (old.title IS DISTINCT FROM new.title)))
  EXECUTE FUNCTION better_supabase.search_index_row('invoice', 'id');

CREATE TRIGGER bsb_search_invoice_index
  AFTER INSERT OR DELETE ON better_supabase.invoices
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('invoice', 'id');

CREATE TRIGGER bsb_search_lease_index_u
  AFTER UPDATE OF id, tenant_id, title ON better_supabase.leases
  FOR EACH ROW
  WHEN (((old.id IS DISTINCT FROM new.id) OR (old.tenant_id IS DISTINCT FROM new.tenant_id) OR (old.title IS DISTINCT FROM new.title)))
  EXECUTE FUNCTION better_supabase.search_index_row('lease', 'id');

CREATE TRIGGER bsb_search_lease_index
  AFTER INSERT OR DELETE ON better_supabase.leases
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('lease', 'id');

CREATE TRIGGER bsb_search_ledger_account_index_u
  AFTER UPDATE OF id, tenant_id, name ON better_supabase.ledger_accounts
  FOR EACH ROW
  WHEN (((old.id IS DISTINCT FROM new.id) OR (old.tenant_id IS DISTINCT FROM new.tenant_id) OR (old.name IS DISTINCT FROM new.name)))
  EXECUTE FUNCTION better_supabase.search_index_row('ledger_account', 'id');

CREATE TRIGGER bsb_search_ledger_account_index
  AFTER INSERT OR DELETE ON better_supabase.ledger_accounts
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('ledger_account', 'id');

CREATE TRIGGER bsb_search_lims_sample_index_u
  AFTER UPDATE OF id, tenant_id, title ON better_supabase.lims_samples
  FOR EACH ROW
  WHEN (((old.id IS DISTINCT FROM new.id) OR (old.tenant_id IS DISTINCT FROM new.tenant_id) OR (old.title IS DISTINCT FROM new.title)))
  EXECUTE FUNCTION better_supabase.search_index_row('lims_sample', 'id');

CREATE TRIGGER bsb_search_lims_sample_index
  AFTER INSERT OR DELETE ON better_supabase.lims_samples
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('lims_sample', 'id');

CREATE TRIGGER bsb_search_maintenance_plan_index_u
  AFTER UPDATE OF id, tenant_id, title ON better_supabase.maintenance_plans
  FOR EACH ROW
  WHEN (((old.id IS DISTINCT FROM new.id) OR (old.tenant_id IS DISTINCT FROM new.tenant_id) OR (old.title IS DISTINCT FROM new.title)))
  EXECUTE FUNCTION better_supabase.search_index_row('maintenance_plan', 'id');

CREATE TRIGGER bsb_search_maintenance_plan_index
  AFTER INSERT OR DELETE ON better_supabase.maintenance_plans
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('maintenance_plan', 'id');

CREATE TRIGGER bsb_search_meeting_decision_index_u
  AFTER UPDATE OF id, tenant_id, title ON better_supabase.meeting_decisions
  FOR EACH ROW
  WHEN (((old.id IS DISTINCT FROM new.id) OR (old.tenant_id IS DISTINCT FROM new.tenant_id) OR (old.title IS DISTINCT FROM new.title)))
  EXECUTE FUNCTION better_supabase.search_index_row('meeting_decision', 'id');

CREATE TRIGGER bsb_search_meeting_decision_index
  AFTER INSERT OR DELETE ON better_supabase.meeting_decisions
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('meeting_decision', 'id');

CREATE TRIGGER bsb_search_meeting_index_u
  AFTER UPDATE OF id, tenant_id, title, location, summary ON better_supabase.meetings
  FOR EACH ROW
  WHEN
    (((old.id IS DISTINCT FROM new.id) OR (old.tenant_id IS DISTINCT FROM new.tenant_id) OR (old.title IS DISTINCT FROM new.title) OR (old.location IS DISTINCT FROM new.location)
    OR (old.summary IS DISTINCT FROM new.summary)))
  EXECUTE FUNCTION better_supabase.search_index_row('meeting', 'id');

CREATE TRIGGER bsb_search_meeting_index
  AFTER INSERT OR DELETE ON better_supabase.meetings
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('meeting', 'id');

CREATE TRIGGER bsb_search_message_index_u
  AFTER UPDATE OF id, tenant_id, body, archived_at ON better_supabase.messages
  FOR EACH ROW
  WHEN
    (((old.id IS DISTINCT FROM new.id) OR (old.tenant_id IS DISTINCT FROM new.tenant_id) OR (old.body IS DISTINCT FROM new.body) OR (old.archived_at IS DISTINCT FROM
    new.archived_at)))
  EXECUTE FUNCTION better_supabase.search_index_row('message', 'id');

CREATE TRIGGER bsb_search_message_index
  AFTER INSERT OR DELETE ON better_supabase.messages
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('message', 'id');

CREATE TRIGGER bsb_search_order_index_u
  AFTER UPDATE OF id, tenant_id, number ON better_supabase.orders
  FOR EACH ROW
  WHEN (((old.id IS DISTINCT FROM new.id) OR (old.tenant_id IS DISTINCT FROM new.tenant_id) OR (old.number IS DISTINCT FROM new.number)))
  EXECUTE FUNCTION better_supabase.search_index_row('order', 'id');

CREATE TRIGGER bsb_search_order_index
  AFTER INSERT OR DELETE ON better_supabase.orders
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('order', 'id');

CREATE TRIGGER bsb_search_person_index_u
  AFTER UPDATE OF id, tenant_id, name, email, phone, title ON better_supabase.people
  FOR EACH ROW
  WHEN
    (((old.id IS DISTINCT FROM new.id) OR (old.tenant_id IS DISTINCT FROM new.tenant_id) OR (old.name IS DISTINCT FROM new.name) OR (old.email IS DISTINCT FROM new.email) OR
    (old.phone IS DISTINCT FROM new.phone) OR (old.title IS DISTINCT FROM new.title)))
  EXECUTE FUNCTION better_supabase.search_index_row('person', 'id');

CREATE TRIGGER bsb_search_person_index
  AFTER INSERT OR DELETE ON better_supabase.people
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('person', 'id');

CREATE TRIGGER bsb_search_post_index_u
  AFTER UPDATE OF id, tenant_id, title, body ON better_supabase.posts
  FOR EACH ROW
  WHEN (((old.id IS DISTINCT FROM new.id) OR (old.tenant_id IS DISTINCT FROM new.tenant_id) OR (old.title IS DISTINCT FROM new.title) OR (old.body IS DISTINCT FROM new.body)))
  EXECUTE FUNCTION better_supabase.search_index_row('post', 'id');

CREATE TRIGGER bsb_search_post_index
  AFTER INSERT OR DELETE ON better_supabase.posts
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('post', 'id');

CREATE TRIGGER bsb_search_product_variant_index_u
  AFTER UPDATE OF id, tenant_id, sku, title, barcode ON better_supabase.product_variants
  FOR EACH ROW
  WHEN
    (((old.id IS DISTINCT FROM new.id) OR (old.tenant_id IS DISTINCT FROM new.tenant_id) OR (old.sku IS DISTINCT FROM new.sku) OR (old.title IS DISTINCT FROM new.title) OR
    (old.barcode IS DISTINCT FROM new.barcode)))
  EXECUTE FUNCTION better_supabase.search_index_row('product_variant', 'id');

CREATE TRIGGER bsb_search_product_variant_index
  AFTER INSERT OR DELETE ON better_supabase.product_variants
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('product_variant', 'id');

CREATE TRIGGER bsb_search_production_order_index_u
  AFTER UPDATE OF id, tenant_id, number, note ON better_supabase.production_orders
  FOR EACH ROW
  WHEN (((old.id IS DISTINCT FROM new.id) OR (old.tenant_id IS DISTINCT FROM new.tenant_id) OR (old.number IS DISTINCT FROM new.number) OR (old.note IS DISTINCT FROM new.note)))
  EXECUTE FUNCTION better_supabase.search_index_row('production_order', 'id');

CREATE TRIGGER bsb_search_production_order_index
  AFTER INSERT OR DELETE ON better_supabase.production_orders
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('production_order', 'id');

CREATE TRIGGER bsb_search_product_index_u
  AFTER UPDATE OF id, tenant_id, title, description, slug ON better_supabase.products
  FOR EACH ROW
  WHEN
    (((old.id IS DISTINCT FROM new.id) OR (old.tenant_id IS DISTINCT FROM new.tenant_id) OR (old.title IS DISTINCT FROM new.title) OR (old.description IS DISTINCT FROM
    new.description) OR (old.slug IS DISTINCT FROM new.slug)))
  EXECUTE FUNCTION better_supabase.search_index_row('product', 'id');

CREATE TRIGGER bsb_search_product_index
  AFTER INSERT OR DELETE ON better_supabase.products
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('product', 'id');

CREATE TRIGGER bsb_search_qualification_type_index_u
  AFTER UPDATE OF id, tenant_id, name, key ON better_supabase.qualification_types
  FOR EACH ROW
  WHEN (((old.id IS DISTINCT FROM new.id) OR (old.tenant_id IS DISTINCT FROM new.tenant_id) OR (old.name IS DISTINCT FROM new.name) OR (old.key IS DISTINCT FROM new.key)))
  EXECUTE FUNCTION better_supabase.search_index_row('qualification_type', 'id');

CREATE TRIGGER bsb_search_qualification_type_index
  AFTER INSERT OR DELETE ON better_supabase.qualification_types
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('qualification_type', 'id');

CREATE TRIGGER bsb_search_quote_index_u
  AFTER UPDATE OF id, tenant_id, title ON better_supabase.quotes
  FOR EACH ROW
  WHEN (((old.id IS DISTINCT FROM new.id) OR (old.tenant_id IS DISTINCT FROM new.tenant_id) OR (old.title IS DISTINCT FROM new.title)))
  EXECUTE FUNCTION better_supabase.search_index_row('quote', 'id');

CREATE TRIGGER bsb_search_quote_index
  AFTER INSERT OR DELETE ON better_supabase.quotes
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('quote', 'id');

CREATE TRIGGER bsb_search_rfq_index_u
  AFTER UPDATE OF id, tenant_id, title ON better_supabase.rfqs
  FOR EACH ROW
  WHEN (((old.id IS DISTINCT FROM new.id) OR (old.tenant_id IS DISTINCT FROM new.tenant_id) OR (old.title IS DISTINCT FROM new.title)))
  EXECUTE FUNCTION better_supabase.search_index_row('rfq', 'id');

CREATE TRIGGER bsb_search_rfq_index
  AFTER INSERT OR DELETE ON better_supabase.rfqs
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('rfq', 'id');

CREATE TRIGGER bsb_search_risk_index_u
  AFTER UPDATE OF id, tenant_id, title, number, description, cause, consequence, archived_at ON better_supabase.risks
  FOR EACH ROW
  WHEN
    (((old.id IS DISTINCT FROM new.id) OR (old.tenant_id IS DISTINCT FROM new.tenant_id) OR (old.title IS DISTINCT FROM new.title) OR (old.number IS DISTINCT FROM new.number) OR
    (old.description IS DISTINCT FROM new.description) OR (old.cause IS DISTINCT FROM new.cause) OR (old.consequence IS DISTINCT FROM new.consequence) OR
    (old.archived_at IS DISTINCT FROM new.archived_at)))
  EXECUTE FUNCTION better_supabase.search_index_row('risk', 'id');

CREATE TRIGGER bsb_search_risk_index
  AFTER INSERT OR DELETE ON better_supabase.risks
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('risk', 'id');

CREATE TRIGGER bsb_search_shipment_index_u
  AFTER UPDATE OF id, tenant_id, reference ON better_supabase.shipments
  FOR EACH ROW
  WHEN (((old.id IS DISTINCT FROM new.id) OR (old.tenant_id IS DISTINCT FROM new.tenant_id) OR (old.reference IS DISTINCT FROM new.reference)))
  EXECUTE FUNCTION better_supabase.search_index_row('shipment', 'id');

CREATE TRIGGER bsb_search_shipment_index
  AFTER INSERT OR DELETE ON better_supabase.shipments
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('shipment', 'id');

CREATE TRIGGER bsb_search_tax_code_index_u
  AFTER UPDATE OF id, tenant_id, name, archived_at ON better_supabase.tax_codes
  FOR EACH ROW
  WHEN
    (((old.id IS DISTINCT FROM new.id) OR (old.tenant_id IS DISTINCT FROM new.tenant_id) OR (old.name IS DISTINCT FROM new.name) OR (old.archived_at IS DISTINCT FROM
    new.archived_at)))
  EXECUTE FUNCTION better_supabase.search_index_row('tax_code', 'id');

CREATE TRIGGER bsb_search_tax_code_index
  AFTER INSERT OR DELETE ON better_supabase.tax_codes
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('tax_code', 'id');

CREATE TRIGGER bsb_search_till_index_u
  AFTER UPDATE OF id, tenant_id, name ON better_supabase.tills
  FOR EACH ROW
  WHEN (((old.id IS DISTINCT FROM new.id) OR (old.tenant_id IS DISTINCT FROM new.tenant_id) OR (old.name IS DISTINCT FROM new.name)))
  EXECUTE FUNCTION better_supabase.search_index_row('till', 'id');

CREATE TRIGGER bsb_search_till_index
  AFTER INSERT OR DELETE ON better_supabase.tills
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('till', 'id');

CREATE TRIGGER bsb_search_vulnerability_index_u
  AFTER UPDATE OF id, tenant_id, vuln_id, summary ON better_supabase.vulnerabilities
  FOR EACH ROW
  WHEN
    (((old.id IS DISTINCT FROM new.id) OR (old.tenant_id IS DISTINCT FROM new.tenant_id) OR (old.vuln_id IS DISTINCT FROM new.vuln_id) OR (old.summary IS DISTINCT FROM
    new.summary)))
  EXECUTE FUNCTION better_supabase.search_index_row('vulnerability', 'id');

CREATE TRIGGER bsb_search_vulnerability_index
  AFTER INSERT OR DELETE ON better_supabase.vulnerabilities
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('vulnerability', 'id');

CREATE TRIGGER bsb_search_warranty_claim_index_u
  AFTER UPDATE OF id, tenant_id, title, manufacturer, decision ON better_supabase.warranty_claims
  FOR EACH ROW
  WHEN
    (((old.id IS DISTINCT FROM new.id) OR (old.tenant_id IS DISTINCT FROM new.tenant_id) OR (old.title IS DISTINCT FROM new.title) OR (old.manufacturer IS DISTINCT FROM
    new.manufacturer) OR (old.decision IS DISTINCT FROM new.decision)))
  EXECUTE FUNCTION better_supabase.search_index_row('warranty_claim', 'id');

CREATE TRIGGER bsb_search_warranty_claim_index
  AFTER INSERT OR DELETE ON better_supabase.warranty_claims
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('warranty_claim', 'id');

CREATE TRIGGER bsb_search_work_center_index_u
  AFTER UPDATE OF id, tenant_id, name, archived_at ON better_supabase.work_centers
  FOR EACH ROW
  WHEN
    (((old.id IS DISTINCT FROM new.id) OR (old.tenant_id IS DISTINCT FROM new.tenant_id) OR (old.name IS DISTINCT FROM new.name) OR (old.archived_at IS DISTINCT FROM
    new.archived_at)))
  EXECUTE FUNCTION better_supabase.search_index_row('work_center', 'id');

CREATE TRIGGER bsb_search_work_center_index
  AFTER INSERT OR DELETE ON better_supabase.work_centers
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('work_center', 'id');

CREATE TRIGGER bsb_search_work_item_index_u
  AFTER UPDATE OF id, tenant_id, title, identifier, body, archived_at ON better_supabase.work_items
  FOR EACH ROW
  WHEN
    (((old.id IS DISTINCT FROM new.id) OR (old.tenant_id IS DISTINCT FROM new.tenant_id) OR (old.title IS DISTINCT FROM new.title) OR (old.identifier IS DISTINCT FROM
    new.identifier) OR (old.body IS DISTINCT FROM new.body) OR (old.archived_at IS DISTINCT FROM new.archived_at)))
  EXECUTE FUNCTION better_supabase.search_index_row('work_item', 'id');

CREATE TRIGGER bsb_search_work_item_index
  AFTER INSERT OR DELETE ON better_supabase.work_items
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('work_item', 'id');

CREATE TRIGGER bsb_search_work_order_index_u
  AFTER UPDATE OF id, tenant_id, title ON better_supabase.work_orders
  FOR EACH ROW
  WHEN (((old.id IS DISTINCT FROM new.id) OR (old.tenant_id IS DISTINCT FROM new.tenant_id) OR (old.title IS DISTINCT FROM new.title)))
  EXECUTE FUNCTION better_supabase.search_index_row('work_order', 'id');

CREATE TRIGGER bsb_search_work_order_index
  AFTER INSERT OR DELETE ON better_supabase.work_orders
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('work_order', 'id');

CREATE TRIGGER bsb_search_project_index_u
  AFTER UPDATE OF id, organization_id, name, deleted_at ON public.projects
  FOR EACH ROW
  WHEN
    (((old.id IS DISTINCT FROM new.id) OR (old.organization_id IS DISTINCT FROM new.organization_id) OR (old.name IS DISTINCT FROM new.name) OR (old.deleted_at IS DISTINCT FROM
    new.deleted_at)))
  EXECUTE FUNCTION better_supabase.search_index_row('project', 'id');

CREATE TRIGGER bsb_search_task_index_u
  AFTER UPDATE OF id, organization_id, title, project_id ON public.tasks
  FOR EACH ROW
  WHEN
    (((old.id IS DISTINCT FROM new.id) OR (old.organization_id IS DISTINCT FROM new.organization_id) OR (old.title IS DISTINCT FROM new.title) OR (old.project_id IS DISTINCT FROM
    new.project_id)))
  EXECUTE FUNCTION better_supabase.search_index_row('task', 'id');

CREATE TRIGGER bsb_search_task_index
  AFTER INSERT OR DELETE ON public.tasks
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('task', 'id');

DROP TRIGGER "bsb_search_project_index" ON "public"."projects";

CREATE TRIGGER bsb_search_project_index
  AFTER INSERT OR DELETE ON public.projects
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('project', 'id');
