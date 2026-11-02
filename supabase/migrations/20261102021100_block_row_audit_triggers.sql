CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.access_requests DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "access_request", "event_prefix": "access_request"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.accounting_accounts DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION
    better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "accounting_account", "event_prefix": "accounting_account"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.accounting_budgets DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "accounting_budget", "event_prefix": "accounting_budget"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.accounting_dimensions DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION
    better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "accounting_dimension", "event_prefix": "accounting_dimension"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.accounting_entries DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "accounting_entry", "event_prefix": "accounting_entry"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.accounting_journals DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION
    better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "accounting_journal", "event_prefix": "accounting_journal"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.accounting_periods DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "accounting_period", "event_prefix": "accounting_period"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.acknowledgement_assignments DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION
    better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "acknowledgement_assignment", "event_prefix": "acknowledgement_assignment"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.acknowledgements DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "acknowledgement", "event_prefix": "acknowledgement"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.activities DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "activity", "event_prefix": "activity"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.agents DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "agent", "event_prefix": "agent"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.ai_chats DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "ai_chat", "event_prefix": "ai_chat"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.ai_documents DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "ai_document", "event_prefix": "ai_document"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.ai_projects DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "ai_project", "event_prefix": "ai_project"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.ai_scheduled_tasks DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "ai_scheduled_task", "event_prefix": "ai_scheduled_task"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.announcements DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "announcement", "event_prefix": "announcement"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.api_keys DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "api_key", "event_prefix": "api_key"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.applications DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "application", "event_prefix": "application"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.appraisal_calibrations DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION
    better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "appraisal_calibration", "event_prefix": "appraisal_calibration"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.appraisal_cycles DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "appraisal_cycle", "event_prefix": "appraisal_cycle"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.appraisal_goals DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "appraisal_goal", "event_prefix": "appraisal_goal"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.appraisal_reviews DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "appraisal_review", "event_prefix": "appraisal_review"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.appraisals DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "appraisal", "event_prefix": "appraisal"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.approval_requests DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "approval", "event_prefix": "approval"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.asset_locations DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "asset_location", "event_prefix": "asset_location"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.assets DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "asset", "event_prefix": "asset"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.assignment_queues DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "assignment_queue", "event_prefix": "assignment_queue"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.attachments DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "attachment", "event_prefix": "attachment"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.automations DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "automation", "event_prefix": "automation"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.bank_accounts DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "bank_account", "event_prefix": "bank_account"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.bank_matches DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "bank_match", "event_prefix": "bank_match"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.bank_rules DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "bank_rule", "event_prefix": "bank_rule"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.bank_statements DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "bank_statement", "event_prefix": "bank_statement"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.bank_transactions DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "bank_transaction", "event_prefix": "bank_transaction"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.bom_components DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "bom_component", "event_prefix": "bom_component"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.bom_operations DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "bom_operation", "event_prefix": "bom_operation"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.boms DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "bom", "event_prefix": "bom"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.bookings DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "booking", "event_prefix": "booking"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.calendar_events DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "calendar_event", "event_prefix": "calendar_event"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.calendars DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "calendar", "event_prefix": "calendar"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.care_alerts DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "care_alert", "event_prefix": "care_alert"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.care_plan_actions DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "care_plan_action", "event_prefix": "care_plan_action"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.care_plan_evaluations DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION
    better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "care_plan_evaluation", "event_prefix": "care_plan_evaluation"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.care_plan_goals DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "care_plan_goal", "event_prefix": "care_plan_goal"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.care_plan_problems DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "care_plan_problem", "event_prefix": "care_plan_problem"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.care_plans DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "care_plan", "event_prefix": "care_plan"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.care_rules DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "care_rule", "event_prefix": "care_rule"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.carts DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "cart", "event_prefix": "cart"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.case_actions DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "case_action", "event_prefix": "case_action"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.case_kinds DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "case_kind", "event_prefix": "case_kind"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.cases DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "case", "event_prefix": "case"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.channels DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "channel", "event_prefix": "channel"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.companies DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "company", "event_prefix": "company"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.compliance_policies DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "compliance_policy", "event_prefix": "compliance_policy"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.connector_servers DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "connector_server", "event_prefix": "connector_server"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.consent_purposes DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "consent_purpose", "event_prefix": "consent_purpose"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.consents DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "consent", "event_prefix": "consent"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.content_entries DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "content_entry", "event_prefix": "content_entry"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.contract_obligations DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION
    better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "contract_obligation", "event_prefix": "contract_obligation"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.contracts DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "contract", "event_prefix": "contract"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.control_frameworks DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "control_framework", "event_prefix": "control_framework"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.controls DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "control", "event_prefix": "control"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.conversations DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "conversation", "event_prefix": "conversation"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.count_plans DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "count_plan", "event_prefix": "count_plan"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.course_certificates DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION
    better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "course_certificate", "event_prefix": "course_certificate"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.course_lessons DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "course_lesson", "event_prefix": "course_lesson"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.course_modules DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "course_module", "event_prefix": "course_module"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.courses DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "course", "event_prefix": "course"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.dam_renditions DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "dam_rendition", "event_prefix": "dam_rendition"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.dam_usage_rights DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "dam_usage_right", "event_prefix": "dam_usage_right"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.deals DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "deal", "event_prefix": "deal"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.dispatch_routes DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "dispatch_route", "event_prefix": "dispatch_route"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.document_suggestions DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION
    better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "document_suggestion", "event_prefix": "document_suggestion"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.document_templates DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "document_template", "event_prefix": "document_template"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.document_text_blocks DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION
    better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "document_text_block", "event_prefix": "document_text_block"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.documents DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "document", "event_prefix": "document"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.donation_funds DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "donation_fund", "event_prefix": "donation_fund"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.donation_receipts DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "donation_receipt", "event_prefix": "donation_receipt"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.donations DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "donation", "event_prefix": "donation"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.drive_nodes DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "drive_node", "event_prefix": "drive_node"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.employees DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "employee", "event_prefix": "employee"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.enrichments DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "enrichment", "event_prefix": "enrichment"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.enrollment_programs DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION
    better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "enrollment_program", "event_prefix": "enrollment_program"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.enrollments DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "enrollment", "event_prefix": "enrollment"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.evidence_tasks DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "evidence_task", "event_prefix": "evidence_task"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.expense_categories DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "expense_category", "event_prefix": "expense_category"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.expense_lines DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "expense_line", "event_prefix": "expense_line"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.expense_reports DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "expense_report", "event_prefix": "expense_report"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.field_definitions DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "field_definition", "event_prefix": "field_definition"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.flags DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["key"], "target_type": "flag", "event_prefix": "flag"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.forecast_snapshots DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "forecast_snapshot", "event_prefix": "forecast_snapshot"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.forms DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "form", "event_prefix": "form"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.funding_awards DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "funding_award", "event_prefix": "funding_award"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.funding_claim_lines DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION
    better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "funding_claim_line", "event_prefix": "funding_claim_line"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.funding_claims DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "funding_claim", "event_prefix": "funding_claim"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.funding_deliveries DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "funding_delivery", "event_prefix": "funding_delivery"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.funding_products DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "funding_product", "event_prefix": "funding_product"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.goals DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "goal", "event_prefix": "goal"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.guest_grants DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "guest_grant", "event_prefix": "guest_grant"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.guests DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "guest", "event_prefix": "guest"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.inboxes DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "inbox", "event_prefix": "inbox"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.incident_postmortems DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION
    better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "incident_postmortem", "event_prefix": "incident_postmortem"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.incident_status_components DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "status_component", "event_prefix": "status_component"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.incident_status_pages DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "status_page", "event_prefix": "status_page"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.incidents DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "incident", "event_prefix": "incident"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.inspection_findings DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION
    better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "inspection_finding", "event_prefix": "inspection_finding"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.inspection_members DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION
    better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["inspection_id", "user_id"], "target_type": "inspection_member", "event_prefix": "inspection_member"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.inspection_programs DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION
    better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "inspection_program", "event_prefix": "inspection_program"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.inspections DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "inspection", "event_prefix": "inspection"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.interviews DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "interview", "event_prefix": "interview"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.inventory_locations DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION
    better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "inventory_location", "event_prefix": "inventory_location"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.inventory_receipts DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "inventory_receipt", "event_prefix": "inventory_receipt"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.invoices DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "invoice", "event_prefix": "invoice"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.iterations DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "iteration", "event_prefix": "iteration"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.job_openings DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "job_opening", "event_prefix": "job_opening"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.knowledge_documents DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION
    better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "knowledge_document", "event_prefix": "knowledge_document"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.leases DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "lease", "event_prefix": "lease"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.ledger_accounts DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "ledger_account", "event_prefix": "ledger_account"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.ledger_holds DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "ledger_hold", "event_prefix": "ledger_hold"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.ledger_transactions DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION
    better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "ledger_transaction", "event_prefix": "ledger_transaction"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.legal_entities DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "legal_entity", "event_prefix": "legal_entity"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.legal_entity_settings DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION
    better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["legal_entity_id", "key"], "target_type": "legal_entity_setting", "event_prefix": "legal_entity_setting"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.lims_methods DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "lims_method", "event_prefix": "lims_method"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.lims_results DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "lims_result", "event_prefix": "lims_result"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.lims_samples DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "lims_sample", "event_prefix": "lims_sample"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.mail_accounts DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "mail_account", "event_prefix": "mail_account"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.mail_messages DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "mail_message", "event_prefix": "mail_message"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.mail_threads DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "mail_thread", "event_prefix": "mail_thread"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.maintenance_calibrations DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION
    better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "maintenance_calibration", "event_prefix": "maintenance_calibration"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.maintenance_meter_readings DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION
    better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "maintenance_meter_reading", "event_prefix": "maintenance_meter_reading"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.maintenance_meters DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "maintenance_meter", "event_prefix": "maintenance_meter"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.maintenance_plan_parts DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION
    better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "maintenance_plan_part", "event_prefix": "maintenance_plan_part"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.maintenance_plans DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "maintenance_plan", "event_prefix": "maintenance_plan"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.maintenance_request_checklist_items DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "checklist_item", "event_prefix": "checklist_item"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.maintenance_requests DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "task", "event_prefix": "task"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.medication_administrations DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION
    better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "medication_administration", "event_prefix": "medication_administration"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.medication_orders DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "medication_order", "event_prefix": "medication_order"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.medications DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "medication", "event_prefix": "medication"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.meeting_action_items DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION
    better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["task_id"], "target_type": "meeting_action_item", "event_prefix": "meeting_action_item"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.meeting_agenda_items DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION
    better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "meeting_agenda_item", "event_prefix": "meeting_agenda_item"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.meeting_attendees DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION
    better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["meeting_id", "user_id"], "target_type": "meeting_attendee", "event_prefix": "meeting_attendee"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.meeting_decisions DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "meeting_decision", "event_prefix": "meeting_decision"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.meetings DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "meeting", "event_prefix": "meeting"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.memories DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "memory", "event_prefix": "memory"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.messages DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "message", "event_prefix": "message"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.moderation_items DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "moderation_item", "event_prefix": "moderation_item"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.observation_definitions DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION
    better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "observation_definition", "event_prefix": "observation_definition"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.observations DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "observation", "event_prefix": "observation"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.orders DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "order", "event_prefix": "order"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.pass_check_ins DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "pass_check_in", "event_prefix": "pass_check_in"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.passes DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "pass", "event_prefix": "pass"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.payroll_lines DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "payroll_line", "event_prefix": "payroll_line"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.payroll_runs DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "payroll_run", "event_prefix": "payroll_run"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.people DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "person", "event_prefix": "person"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.pick_lines DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "pick_line", "event_prefix": "pick_line"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.pick_lists DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "pick_list", "event_prefix": "pick_list"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.pick_waves DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "pick_wave", "event_prefix": "pick_wave"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.pipelines DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "pipeline", "event_prefix": "pipeline"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.pledges DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "pledge", "event_prefix": "pledge"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.post_boards DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "post_board", "event_prefix": "post_board"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.posts DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "post", "event_prefix": "post"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.product_variants DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "product_variant", "event_prefix": "product_variant"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.production_consumptions DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION
    better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "production_consumption", "event_prefix": "production_consumption"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.production_order_operations DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION
    better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "production_order_operation", "event_prefix": "production_order_operation"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.production_orders DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "production_order", "event_prefix": "production_order"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.products DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "product", "event_prefix": "product"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.promotions DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "promotion", "event_prefix": "promotion"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.purchase_orders DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "purchase_order", "event_prefix": "purchase_order"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.purchase_requisitions DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION
    better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "purchase_requisition", "event_prefix": "purchase_requisition"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.qualification_requirements DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION
    better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "qualification_requirement", "event_prefix": "qualification_requirement"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.qualification_types DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION
    better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "qualification_type", "event_prefix": "qualification_type"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.qualifications DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "qualification", "event_prefix": "qualification"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.quotes DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "quote", "event_prefix": "quote"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.reactions DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "reaction", "event_prefix": "reaction"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.relations DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "relation", "event_prefix": "relation"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.reminders DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "reminder", "event_prefix": "reminder"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.rendered_documents DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "document_snapshot", "event_prefix": "document_snapshot"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.rfq_lines DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "rfq_line", "event_prefix": "rfq_line"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.rfq_quote_lines DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "rfq_quote_line", "event_prefix": "rfq_quote_line"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.rfq_quotes DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "rfq_quote", "event_prefix": "rfq_quote"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.rfq_suppliers DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "rfq_supplier", "event_prefix": "rfq_supplier"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.rfqs DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "rfq", "event_prefix": "rfq"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.risk_assessments DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "risk_assessment", "event_prefix": "risk_assessment"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.risk_matrices DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "risk_matrix", "event_prefix": "risk_matrix"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.risks DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "risk", "event_prefix": "risk"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.score_models DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "score_model", "event_prefix": "score_model"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.segments DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "segment", "event_prefix": "segment"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.sequences DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "sequence", "event_prefix": "sequence"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.share_links DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "share_link", "event_prefix": "share_link"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.shared_views DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "saved_view", "event_prefix": "saved_view"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.shift_assignments DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "shift_assignment", "event_prefix": "shift_assignment"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.shift_availability DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION
    better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "shift_availability", "event_prefix": "shift_availability"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.shift_swaps DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "shift_swap", "event_prefix": "shift_swap"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.shift_templates DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "shift_template", "event_prefix": "shift_template"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.shifts DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "shift", "event_prefix": "shift"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.shipment_lines DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "shipment_line", "event_prefix": "shipment_line"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.shipment_packages DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "shipment_package", "event_prefix": "shipment_package"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.shipment_tracking_events DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION
    better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "shipment_tracking_event", "event_prefix": "shipment_tracking_event"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.shipments DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "shipment", "event_prefix": "shipment"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.signature_requests DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "signature_request", "event_prefix": "signature_request"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.sla_policies DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "sla_policy", "event_prefix": "sla_policy"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.stock_lot_links DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION
    better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["parent_lot_id", "child_lot_id", "order_id"], "target_type": "stock_lot_link", "event_prefix": "stock_lot_link"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.tags DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "tag", "event_prefix": "tag"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.tax_codes DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "tax_code", "event_prefix": "tax_code"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.tax_rates DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "tax_rate", "event_prefix": "tax_rate"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.tax_returns DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "tax_return", "event_prefix": "tax_return"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.teams DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "team", "event_prefix": "team"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.templates DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "template", "event_prefix": "template"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.till_counts DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "till_count", "event_prefix": "till_count"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.till_deposits DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "till_deposit", "event_prefix": "till_deposit"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.till_movements DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "till_movement", "event_prefix": "till_movement"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.till_sessions DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "till_session", "event_prefix": "till_session"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.tills DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "till", "event_prefix": "till"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.time_entries DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "time_entry", "event_prefix": "time_entry"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.time_rates DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "time_rate", "event_prefix": "time_rate"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.timeline_entries DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "timeline_entry", "event_prefix": "timeline_entry"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.timesheets DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "timesheet", "event_prefix": "timesheet"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.versions DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "version", "event_prefix": "version"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.waitlist_entries DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "waitlist_entry", "event_prefix": "waitlist_entry"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.webhook_endpoints DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "webhook_endpoint", "event_prefix": "webhook_endpoint"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.work_centers DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "work_center", "event_prefix": "work_center"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.work_item_checklist_items DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "checklist_item", "event_prefix": "checklist_item"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.work_items DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "task", "event_prefix": "task"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.work_order_parts DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "work_order_part", "event_prefix": "work_order_part"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.work_orders DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "work_order", "event_prefix": "work_order"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.work_projects DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "project", "event_prefix": "project"}');

CREATE CONSTRAINT TRIGGER bsb_audit
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.workflow_definitions DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  EXECUTE FUNCTION
    better_supabase.audit_row_change('{"ignore": [], "redact": [], "key_columns": ["id"], "target_type": "workflow_definition", "event_prefix": "workflow_definition"}');
