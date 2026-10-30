SET local check_function_bodies = off;

DROP POLICY "bsb_tenant_scope_select" ON "better_supabase"."memories";

DROP POLICY "memories_read" ON "better_supabase"."memories";

DROP FUNCTION "api"."purge_memories"(integer, integer);

DROP FUNCTION "api"."set_knowledge_collection_grant"(uuid, uuid, text, boolean);

DROP FUNCTION "better_supabase"."purge_memories"(integer, integer);

DROP FUNCTION "better_supabase"."set_knowledge_collection_grant"(uuid, uuid, text, boolean);

CREATE OR REPLACE FUNCTION api.purge_memories (
  retention_days integer DEFAULT 30,
  batch          integer DEFAULT 1000,
  tenant         uuid    DEFAULT NULL::uuid
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."purge_memories"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.set_knowledge_collection_grant (
  collection_id uuid,
  user_id       uuid    DEFAULT NULL::uuid,
  team_id       uuid    DEFAULT NULL::uuid,
  granted       boolean DEFAULT true
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_knowledge_collection_grant"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION better_supabase.data_lifecycle_tables()
  RETURNS TABLE (
    subject  text,
    name     text,
    tbl      text,
    col      text,
    purge    boolean,
    omit     text[],
    exported boolean
  )
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select t.subject, t.name, t.tbl, t.col, t.purge,
    t.omit || array(
      select a.attname::text
      from pg_catalog.pg_attribute a
      where a.attrelid = to_regclass(t.tbl)
        and a.attnum > 0
        and not a.attisdropped
        and a.attname ~* 'token|secret|_hash|password|api_key|license_key'
        and a.attname <> t.col
        and not a.attname = any(t.omit)
      order by a.attnum
    ) as omit,
    t.exported
  from (
  select * from (values
    ('user', 'better_supabase.audit_events', '"better_supabase"."audit_events"', 'actor_id', false, array['old_record', 'new_record', 'impersonated_by', 'impersonation_reason', 'support_session_id']::text[], true),
    ('user', 'public.memberships', '"public"."memberships"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.platform_roles', '"better_supabase"."platform_roles"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.profiles', '"better_supabase"."profiles"', 'id', true, '{}'::text[], true),
    ('user', 'better_supabase.notification_recipients', '"better_supabase"."notification_recipients"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.notification_subscriptions', '"better_supabase"."notification_subscriptions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.notification_preferences', '"better_supabase"."notification_preferences"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.notification_suppressions', '"better_supabase"."notification_suppressions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.user_settings', '"better_supabase"."user_settings"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.usage_history', '"better_supabase"."usage_history"', 'actor_id', true, '{}'::text[], true),
    ('user', 'better_supabase.flag_overrides', '"better_supabase"."flag_overrides"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.drive_nodes', '"better_supabase"."drive_nodes"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.drive_drives', '"better_supabase"."drive_drives"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.drive_connections', '"better_supabase"."drive_connections"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.guests', '"better_supabase"."guests"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.attachments', '"better_supabase"."attachments"', 'uploaded_by', true, '{}'::text[], true),
    ('user', 'better_supabase.attachment_versions', '"better_supabase"."attachment_versions"', 'uploaded_by', true, '{}'::text[], true),
    ('user', 'better_supabase.scim_users', '"better_supabase"."scim_users"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.enrollment_programs', '"better_supabase"."enrollment_programs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.enrollments', '"better_supabase"."enrollments"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.waitlist_entries', '"better_supabase"."waitlist_entries"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.invite_code_redemptions', '"better_supabase"."invite_code_redemptions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.announcement_dismissals', '"better_supabase"."announcement_dismissals"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.streams', '"better_supabase"."streams"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_runs', '"better_supabase"."workflow_runs"', 'actor_id', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_schedules', '"better_supabase"."workflow_schedules"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_start_requests', '"better_supabase"."workflow_start_requests"', 'actor_id', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_definitions', '"better_supabase"."workflow_definitions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_opt_outs', '"better_supabase"."workflow_opt_outs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_definition_grants', '"better_supabase"."workflow_definition_grants"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.inbox_members', '"better_supabase"."inbox_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.inbox_team_members', '"better_supabase"."inbox_team_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.contacts', '"better_supabase"."contacts"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.scheduled_inbox_messages', '"better_supabase"."scheduled_inbox_messages"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.inbox_drafts', '"better_supabase"."inbox_drafts"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_projects', '"better_supabase"."ai_projects"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_chats', '"better_supabase"."ai_chats"', 'owner_id', true, array['search_tsv']::text[], true),
    ('user', 'better_supabase.ai_chat_participants', '"better_supabase"."ai_chat_participants"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_messages', '"better_supabase"."ai_messages"', 'owner_id', true, array['search_tsv']::text[], true),
    ('user', 'better_supabase.ai_runs', '"better_supabase"."ai_runs"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_tool_approvals', '"better_supabase"."ai_tool_approvals"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_pending_inputs', '"better_supabase"."ai_pending_inputs"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_message_feedback', '"better_supabase"."ai_message_feedback"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_chat_shares', '"better_supabase"."ai_chat_shares"', 'created_by', true, array['token_hash']::text[], true),
    ('user', 'better_supabase.ai_moderation_events', '"better_supabase"."ai_moderation_events"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_run_steps', '"better_supabase"."ai_run_steps"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_sandboxes', '"better_supabase"."ai_sandboxes"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_harness_sessions', '"better_supabase"."ai_harness_sessions"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_files', '"better_supabase"."ai_files"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_documents', '"better_supabase"."ai_documents"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_document_versions', '"better_supabase"."ai_document_versions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_suggestions', '"better_supabase"."ai_suggestions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.knowledge_documents', '"better_supabase"."knowledge_documents"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.knowledge_collection_grants', '"better_supabase"."knowledge_collection_grants"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.memories', '"better_supabase"."memories"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_message_embeddings', '"better_supabase"."ai_message_embeddings"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.agents', '"better_supabase"."agents"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.agent_installs', '"better_supabase"."agent_installs"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.agent_ratings', '"better_supabase"."agent_ratings"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.connector_grants', '"better_supabase"."connector_grants"', 'user_id', true, array['credential_ref']::text[], true),
    ('user', 'better_supabase.connector_sessions', '"better_supabase"."connector_sessions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_scheduled_tasks', '"better_supabase"."ai_scheduled_tasks"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_task_runs', '"better_supabase"."ai_task_runs"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.push_devices', '"better_supabase"."push_devices"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_batches', '"better_supabase"."ai_batches"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.teams', '"better_supabase"."teams"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.team_members', '"better_supabase"."team_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.status_history', '"better_supabase"."status_history"', 'actor_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.share_links', '"better_supabase"."share_links"', 'created_by', true, array['token_hash', 'password_hash']::text[], true),
    ('user', 'better_supabase.reminders', '"better_supabase"."reminders"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.import_runs', '"better_supabase"."import_runs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.subject_members', '"better_supabase"."subject_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.saved_view_preferences', '"better_supabase"."saved_view_preferences"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.bulk_runs', '"better_supabase"."bulk_runs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.calendar_events', '"better_supabase"."calendar_events"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.calendar_attendees', '"better_supabase"."calendar_attendees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.calendar_working_hours', '"better_supabase"."calendar_working_hours"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.bookings', '"better_supabase"."bookings"', 'customer_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.versions', '"better_supabase"."versions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.trash_items', '"better_supabase"."trash_items"', 'trashed_by', true, '{}'::text[], true),
    ('user', 'better_supabase.reactions', '"better_supabase"."reactions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.custom_emoji', '"better_supabase"."custom_emoji"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.approval_requests', '"better_supabase"."approval_requests"', 'requested_by', true, '{}'::text[], true),
    ('user', 'better_supabase.approval_decisions', '"better_supabase"."approval_decisions"', 'approver', true, '{}'::text[], true),
    ('user', 'better_supabase.approval_policies', '"better_supabase"."approval_policies"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.access_requests', '"better_supabase"."access_requests"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.documents', '"better_supabase"."documents"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.document_updates', '"better_supabase"."document_updates"', 'actor', true, '{}'::text[], true),
    ('user', 'better_supabase.document_suggestions', '"better_supabase"."document_suggestions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.ledger_accounts', '"better_supabase"."ledger_accounts"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.carts', '"better_supabase"."carts"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.forms', '"better_supabase"."forms"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.form_versions', '"better_supabase"."form_versions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.form_submissions', '"better_supabase"."form_submissions"', 'respondent_id', true, '{}'::text[], true),
    ('user', 'better_supabase.signature_requests', '"better_supabase"."signature_requests"', 'requested_by', true, '{}'::text[], true),
    ('user', 'better_supabase.signatures', '"better_supabase"."signatures"', 'signer', true, '{}'::text[], true),
    ('user', 'better_supabase.time_entries', '"better_supabase"."time_entries"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.timesheets', '"better_supabase"."timesheets"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.template_schedules', '"better_supabase"."template_schedules"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.deals', '"better_supabase"."deals"', 'owner_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.deal_members', '"better_supabase"."deal_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.application_scorecards', '"better_supabase"."application_scorecards"', 'reviewer_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.work_items', '"better_supabase"."work_items"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.work_item_checklist_items', '"better_supabase"."work_item_checklist_items"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.work_item_assignees', '"better_supabase"."work_item_assignees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.pipeline_stage_history', '"better_supabase"."pipeline_stage_history"', 'actor_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.engagements', '"better_supabase"."engagements"', 'owner_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.quotes', '"better_supabase"."quotes"', 'owner_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.employees', '"better_supabase"."employees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.employee_private_details', '"better_supabase"."employee_private_details"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.moderation_reports', '"better_supabase"."moderation_reports"', 'reporter_id', true, '{}'::text[], true),
    ('user', 'better_supabase.moderation_bans', '"better_supabase"."moderation_bans"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.assets', '"better_supabase"."assets"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.score_models', '"better_supabase"."score_models"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.score_model_versions', '"better_supabase"."score_model_versions"', 'saved_by', true, '{}'::text[], true),
    ('user', 'better_supabase.passes', '"better_supabase"."passes"', 'holder_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.lease_agreements', '"better_supabase"."lease_agreements"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.expense_reports', '"better_supabase"."expense_reports"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.pledges', '"better_supabase"."pledges"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.donations', '"better_supabase"."donations"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.work_orders', '"better_supabase"."work_orders"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.dispatch_routes', '"better_supabase"."dispatch_routes"', 'technician_id', true, '{}'::text[], true),
    ('user', 'better_supabase.work_order_parts', '"better_supabase"."work_order_parts"', 'recorded_by', true, '{}'::text[], true),
    ('user', 'better_supabase.shipments', '"better_supabase"."shipments"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.contracts', '"better_supabase"."contracts"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.control_evidence', '"better_supabase"."control_evidence"', 'collected_by', true, '{}'::text[], true),
    ('user', 'better_supabase.policy_acknowledgements', '"better_supabase"."policy_acknowledgements"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.incident_updates', '"better_supabase"."incident_updates"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.courses', '"better_supabase"."courses"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.course_lesson_progress', '"better_supabase"."course_lesson_progress"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.course_certificates', '"better_supabase"."course_certificates"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.conversations', '"better_supabase"."conversations"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.conversation_members', '"better_supabase"."conversation_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.messages', '"better_supabase"."messages"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.message_edits', '"better_supabase"."message_edits"', 'edited_by', true, '{}'::text[], true),
    ('user', 'better_supabase.thread_reads', '"better_supabase"."thread_reads"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.channels', '"better_supabase"."channels"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.mail_accounts', '"better_supabase"."mail_accounts"', 'user_id', true, array['credential_ref']::text[], true),
    ('user', 'better_supabase.assignment_queue_members', '"better_supabase"."assignment_queue_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.sequences', '"better_supabase"."sequences"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.sequence_enrollments', '"better_supabase"."sequence_enrollments"', 'enrolled_by', true, '{}'::text[], true),
    ('user', 'better_supabase.post_boards', '"better_supabase"."post_boards"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.posts', '"better_supabase"."posts"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.content_entries', '"better_supabase"."content_entries"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.risk_assessments', '"better_supabase"."risk_assessments"', 'assessed_by', true, '{}'::text[], true),
    ('organization', 'better_supabase.audit_events', '"better_supabase"."audit_events"', 'organization_id', false, array['old_record', 'new_record', 'impersonated_by', 'impersonation_reason', 'support_session_id']::text[], true),
    ('organization', 'public.memberships', '"public"."memberships"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invitations', '"better_supabase"."invitations"', 'organization_id', true, array['token_hash']::text[], true),
    ('organization', 'better_supabase.permission_overrides', '"better_supabase"."permission_overrides"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.outbox_events', '"better_supabase"."outbox_events"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_events', '"better_supabase"."notification_events"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_recipients', '"better_supabase"."notification_recipients"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_deliveries', '"better_supabase"."notification_deliveries"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_delivery_events', '"better_supabase"."notification_delivery_events"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_subscriptions', '"better_supabase"."notification_subscriptions"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_preferences', '"better_supabase"."notification_preferences"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.webhook_endpoints', '"better_supabase"."webhook_endpoints"', 'organization_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.webhook_endpoint_secrets', '"better_supabase"."webhook_endpoint_secrets"', 'organization_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.webhook_deliveries', '"better_supabase"."webhook_deliveries"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.api_keys', '"better_supabase"."api_keys"', 'organization_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.organization_settings', '"better_supabase"."organization_settings"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_counters', '"better_supabase"."usage_counters"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_events', '"better_supabase"."usage_events"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_history', '"better_supabase"."usage_history"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_distinct', '"better_supabase"."usage_distinct"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_quotas', '"better_supabase"."usage_quotas"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.flag_overrides', '"better_supabase"."flag_overrides"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_nodes', '"better_supabase"."drive_nodes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_grants', '"better_supabase"."drive_grants"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_drives', '"better_supabase"."drive_drives"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_drive_grants', '"better_supabase"."drive_drive_grants"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_connections', '"better_supabase"."drive_connections"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.guests', '"better_supabase"."guests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.guest_grants', '"better_supabase"."guest_grants"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.comment_tasks', '"better_supabase"."comment_tasks"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.attachments', '"better_supabase"."attachments"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.attachment_versions', '"better_supabase"."attachment_versions"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.retention_policies', '"better_supabase"."retention_policies"', 'organization_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.organization_domains', '"better_supabase"."organization_domains"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.organization_sso_providers', '"better_supabase"."organization_sso_providers"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.scim_users', '"better_supabase"."scim_users"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.scim_groups', '"better_supabase"."scim_groups"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.enrollment_programs', '"better_supabase"."enrollment_programs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.enrollments', '"better_supabase"."enrollments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.enrollment_steps', '"better_supabase"."enrollment_steps"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invite_codes', '"better_supabase"."invite_codes"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.streams', '"better_supabase"."streams"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_runs', '"better_supabase"."workflow_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_schedules', '"better_supabase"."workflow_schedules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_start_requests', '"better_supabase"."workflow_start_requests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_definitions', '"better_supabase"."workflow_definitions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_opt_outs', '"better_supabase"."workflow_opt_outs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_credentials', '"better_supabase"."workflow_credentials"', 'tenant_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.chat_installations', '"better_supabase"."chat_installations"', 'tenant_id', false, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.inboxes', '"better_supabase"."inboxes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_teams', '"better_supabase"."inbox_teams"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.contacts', '"better_supabase"."contacts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.contact_identities', '"better_supabase"."contact_identities"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_conversations', '"better_supabase"."inbox_conversations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.conversation_events', '"better_supabase"."conversation_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_message_details', '"better_supabase"."inbox_message_details"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.message_deliveries', '"better_supabase"."message_deliveries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbound_events', '"better_supabase"."inbound_events"', 'tenant_id', true, array['headers']::text[], true),
    ('organization', 'better_supabase.message_templates', '"better_supabase"."message_templates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.scheduled_inbox_messages', '"better_supabase"."scheduled_inbox_messages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_drafts', '"better_supabase"."inbox_drafts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_projects', '"better_supabase"."ai_projects"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_chats', '"better_supabase"."ai_chats"', 'organization_id', true, array['search_tsv']::text[], true),
    ('organization', 'better_supabase.ai_tool_policies', '"better_supabase"."ai_tool_policies"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_moderation_events', '"better_supabase"."ai_moderation_events"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_sandboxes', '"better_supabase"."ai_sandboxes"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_files', '"better_supabase"."ai_files"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_documents', '"better_supabase"."ai_documents"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.knowledge_documents', '"better_supabase"."knowledge_documents"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.knowledge_collections', '"better_supabase"."knowledge_collections"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.knowledge_collection_grants', '"better_supabase"."knowledge_collection_grants"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.memories', '"better_supabase"."memories"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_message_embeddings', '"better_supabase"."ai_message_embeddings"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.agents', '"better_supabase"."agents"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.agent_installs', '"better_supabase"."agent_installs"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.connector_servers', '"better_supabase"."connector_servers"', 'organization_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.connector_grants', '"better_supabase"."connector_grants"', 'organization_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.ai_scheduled_tasks', '"better_supabase"."ai_scheduled_tasks"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_task_runs', '"better_supabase"."ai_task_runs"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_cache_entries', '"better_supabase"."ai_cache_entries"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_provider_keys', '"better_supabase"."ai_provider_keys"', 'organization_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.ai_batches', '"better_supabase"."ai_batches"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_batch_items', '"better_supabase"."ai_batch_items"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.number_sequences', '"better_supabase"."number_sequences"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.teams', '"better_supabase"."teams"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.team_members', '"better_supabase"."team_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.tags', '"better_supabase"."tags"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.taggings', '"better_supabase"."taggings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.status_history', '"better_supabase"."status_history"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.status_stages', '"better_supabase"."status_stages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.subject_lifecycles', '"better_supabase"."subject_lifecycles"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.field_definitions', '"better_supabase"."field_definitions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.field_values', '"better_supabase"."field_values"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.share_links', '"better_supabase"."share_links"', 'tenant_id', true, array['token_hash', 'password_hash']::text[], true),
    ('organization', 'better_supabase.recurrence_rules', '"better_supabase"."recurrence_rules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.reminders', '"better_supabase"."reminders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.import_runs', '"better_supabase"."import_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.subject_members', '"better_supabase"."subject_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shared_views', '"better_supabase"."shared_views"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.saved_view_preferences', '"better_supabase"."saved_view_preferences"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.relations', '"better_supabase"."relations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bulk_runs', '"better_supabase"."bulk_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.products', '"better_supabase"."products"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_options', '"better_supabase"."product_options"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_option_values', '"better_supabase"."product_option_values"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_variants', '"better_supabase"."product_variants"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_variant_values', '"better_supabase"."product_variant_values"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.price_lists', '"better_supabase"."price_lists"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_prices', '"better_supabase"."product_prices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.categories', '"better_supabase"."categories"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_categories', '"better_supabase"."product_categories"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_collections', '"better_supabase"."product_collections"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.collection_products', '"better_supabase"."collection_products"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.storefronts', '"better_supabase"."storefronts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.catalog_channels', '"better_supabase"."catalog_channels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.catalog_channel_products', '"better_supabase"."catalog_channel_products"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_translations', '"better_supabase"."product_translations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_variant_translations', '"better_supabase"."product_variant_translations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_media', '"better_supabase"."product_media"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.search_documents', '"better_supabase"."search_documents"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.metric_points', '"better_supabase"."metric_points"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.calendars', '"better_supabase"."calendars"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.calendar_events', '"better_supabase"."calendar_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.calendar_attendees', '"better_supabase"."calendar_attendees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.calendar_event_alarms', '"better_supabase"."calendar_event_alarms"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.calendar_working_hours', '"better_supabase"."calendar_working_hours"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.booking_resources', '"better_supabase"."booking_resources"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.booking_availability', '"better_supabase"."booking_availability"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.booking_exceptions', '"better_supabase"."booking_exceptions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.booking_services', '"better_supabase"."booking_services"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bookings', '"better_supabase"."bookings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.versions', '"better_supabase"."versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.trash_items', '"better_supabase"."trash_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.reactions', '"better_supabase"."reactions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.reaction_scores', '"better_supabase"."reaction_scores"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.custom_emoji', '"better_supabase"."custom_emoji"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.approval_requests', '"better_supabase"."approval_requests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.approval_decisions', '"better_supabase"."approval_decisions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.approval_policies', '"better_supabase"."approval_policies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.access_requests', '"better_supabase"."access_requests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.documents', '"better_supabase"."documents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_updates', '"better_supabase"."document_updates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_snapshots', '"better_supabase"."document_snapshots"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_suggestions', '"better_supabase"."document_suggestions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ledger_accounts', '"better_supabase"."ledger_accounts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ledger_transactions', '"better_supabase"."ledger_transactions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ledger_entries', '"better_supabase"."ledger_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ledger_balances', '"better_supabase"."ledger_balances"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ledger_holds', '"better_supabase"."ledger_holds"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inventory_locations', '"better_supabase"."inventory_locations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_levels', '"better_supabase"."stock_levels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_reservations', '"better_supabase"."stock_reservations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_transfers', '"better_supabase"."stock_transfers"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_transfer_lines', '"better_supabase"."stock_transfer_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.purchase_orders', '"better_supabase"."purchase_orders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.purchase_order_lines', '"better_supabase"."purchase_order_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_items', '"better_supabase"."stock_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_bins', '"better_supabase"."stock_bins"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_lots', '"better_supabase"."stock_lots"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_serials', '"better_supabase"."stock_serials"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_buckets', '"better_supabase"."stock_buckets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_allocations', '"better_supabase"."stock_allocations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.carts', '"better_supabase"."carts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.cart_lines', '"better_supabase"."cart_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shipping_rates', '"better_supabase"."shipping_rates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.orders', '"better_supabase"."orders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_lines', '"better_supabase"."order_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_payments', '"better_supabase"."order_payments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.fulfillments', '"better_supabase"."fulfillments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.fulfillment_lines', '"better_supabase"."fulfillment_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_returns', '"better_supabase"."order_returns"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_return_lines', '"better_supabase"."order_return_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_refunds', '"better_supabase"."order_refunds"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.promotions', '"better_supabase"."promotions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.promotion_codes', '"better_supabase"."promotion_codes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.cart_promotion_codes', '"better_supabase"."cart_promotion_codes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.promotion_redemptions', '"better_supabase"."promotion_redemptions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.forms', '"better_supabase"."forms"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.form_versions', '"better_supabase"."form_versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.form_submissions', '"better_supabase"."form_submissions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.form_answer_keys', '"better_supabase"."form_answer_keys"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.signature_requests', '"better_supabase"."signature_requests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.signatures', '"better_supabase"."signatures"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.time_entries', '"better_supabase"."time_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.timesheets', '"better_supabase"."timesheets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.service_principals', '"better_supabase"."service_principals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.templates', '"better_supabase"."templates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.template_applications', '"better_supabase"."template_applications"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.template_schedules', '"better_supabase"."template_schedules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.template_schedule_runs', '"better_supabase"."template_schedule_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deals', '"better_supabase"."deals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deal_contacts', '"better_supabase"."deal_contacts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deal_members', '"better_supabase"."deal_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deal_lines', '"better_supabase"."deal_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.job_openings', '"better_supabase"."job_openings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.applications', '"better_supabase"."applications"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.application_scorecards', '"better_supabase"."application_scorecards"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.interviews', '"better_supabase"."interviews"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_items', '"better_supabase"."work_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_item_checklist_items', '"better_supabase"."work_item_checklist_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_item_assignees', '"better_supabase"."work_item_assignees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_projects', '"better_supabase"."work_projects"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.iterations', '"better_supabase"."iterations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pipelines', '"better_supabase"."pipelines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pipeline_stages', '"better_supabase"."pipeline_stages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pipeline_transitions', '"better_supabase"."pipeline_transitions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pipeline_stage_history', '"better_supabase"."pipeline_stage_history"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.companies', '"better_supabase"."companies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.people', '"better_supabase"."people"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.company_people', '"better_supabase"."company_people"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.person_inbox_contacts', '"better_supabase"."person_inbox_contacts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.engagements', '"better_supabase"."engagements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.engagement_subjects', '"better_supabase"."engagement_subjects"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quotes', '"better_supabase"."quotes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_lines', '"better_supabase"."quote_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_versions', '"better_supabase"."quote_versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_version_lines', '"better_supabase"."quote_version_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_tax_lines', '"better_supabase"."quote_tax_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoices', '"better_supabase"."invoices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_lines', '"better_supabase"."invoice_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_charges', '"better_supabase"."invoice_charges"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sla_policies', '"better_supabase"."sla_policies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sla_clocks', '"better_supabase"."sla_clocks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.targets', '"better_supabase"."targets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employees', '"better_supabase"."employees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employee_private_details', '"better_supabase"."employee_private_details"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employee_contracts', '"better_supabase"."employee_contracts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_items', '"better_supabase"."moderation_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_reports', '"better_supabase"."moderation_reports"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_actions', '"better_supabase"."moderation_actions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_bans', '"better_supabase"."moderation_bans"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rules', '"better_supabase"."rules"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rule_versions', '"better_supabase"."rule_versions"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rule_evaluations', '"better_supabase"."rule_evaluations"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.asset_locations', '"better_supabase"."asset_locations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.assets', '"better_supabase"."assets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.asset_assignments', '"better_supabase"."asset_assignments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.score_models', '"better_supabase"."score_models"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.score_model_versions', '"better_supabase"."score_model_versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.scores', '"better_supabase"."scores"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.passes', '"better_supabase"."passes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pass_check_ins', '"better_supabase"."pass_check_ins"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.time_rates', '"better_supabase"."time_rates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.time_invoice_entries', '"better_supabase"."time_invoice_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.lease_agreements', '"better_supabase"."lease_agreements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.lease_charges', '"better_supabase"."lease_charges"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.expense_categories', '"better_supabase"."expense_categories"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.expense_reports', '"better_supabase"."expense_reports"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.expense_lines', '"better_supabase"."expense_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.donation_funds', '"better_supabase"."donation_funds"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pledges', '"better_supabase"."pledges"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.donation_receipts', '"better_supabase"."donation_receipts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.donations', '"better_supabase"."donations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_orders', '"better_supabase"."work_orders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.dispatch_routes', '"better_supabase"."dispatch_routes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.dispatch_route_stops', '"better_supabase"."dispatch_route_stops"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_order_parts', '"better_supabase"."work_order_parts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shipments', '"better_supabase"."shipments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shipment_packages', '"better_supabase"."shipment_packages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shipment_tracking_events', '"better_supabase"."shipment_tracking_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shipment_lines', '"better_supabase"."shipment_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.contracts', '"better_supabase"."contracts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.contract_obligations', '"better_supabase"."contract_obligations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.control_frameworks', '"better_supabase"."control_frameworks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.controls', '"better_supabase"."controls"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.control_evidence', '"better_supabase"."control_evidence"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.evidence_tasks', '"better_supabase"."evidence_tasks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.policies', '"better_supabase"."policies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.policy_acknowledgements', '"better_supabase"."policy_acknowledgements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.status_components', '"better_supabase"."status_components"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.status_component_history', '"better_supabase"."status_component_history"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incidents', '"better_supabase"."incidents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_updates', '"better_supabase"."incident_updates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_impacts', '"better_supabase"."incident_impacts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_postmortems', '"better_supabase"."incident_postmortems"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.status_pages', '"better_supabase"."status_pages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.courses', '"better_supabase"."courses"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.course_modules', '"better_supabase"."course_modules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.course_lessons', '"better_supabase"."course_lessons"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.course_lesson_progress', '"better_supabase"."course_lesson_progress"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.course_certificates', '"better_supabase"."course_certificates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.conversations', '"better_supabase"."conversations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.conversation_members', '"better_supabase"."conversation_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.messages', '"better_supabase"."messages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.message_edits', '"better_supabase"."message_edits"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.thread_reads', '"better_supabase"."thread_reads"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.message_record_mentions', '"better_supabase"."message_record_mentions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.thread_summaries', '"better_supabase"."thread_summaries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.channels', '"better_supabase"."channels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.activity_entries', '"better_supabase"."activity_entries"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.mail_accounts', '"better_supabase"."mail_accounts"', 'tenant_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.mail_threads', '"better_supabase"."mail_threads"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.mail_messages', '"better_supabase"."mail_messages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.mail_tracked_links', '"better_supabase"."mail_tracked_links"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.mail_tracking_events', '"better_supabase"."mail_tracking_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.mail_thread_subjects', '"better_supabase"."mail_thread_subjects"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.segments', '"better_supabase"."segments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.segment_members', '"better_supabase"."segment_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.assignment_queues', '"better_supabase"."assignment_queues"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.assignment_queue_members', '"better_supabase"."assignment_queue_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.assignments', '"better_supabase"."assignments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.enrichments', '"better_supabase"."enrichments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.forecast_snapshots', '"better_supabase"."forecast_snapshots"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.forecast_snapshot_deals', '"better_supabase"."forecast_snapshot_deals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.field_changes', '"better_supabase"."field_changes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sequences', '"better_supabase"."sequences"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sequence_enrollments', '"better_supabase"."sequence_enrollments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.lead_score_checks', '"better_supabase"."lead_score_checks"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.post_boards', '"better_supabase"."post_boards"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.posts', '"better_supabase"."posts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.content_entries', '"better_supabase"."content_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.qualification_types', '"better_supabase"."qualification_types"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.qualification_requirements', '"better_supabase"."qualification_requirements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.qualifications', '"better_supabase"."qualifications"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.risk_matrices', '"better_supabase"."risk_matrices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.risks', '"better_supabase"."risks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.risk_assessments', '"better_supabase"."risk_assessments"', 'tenant_id', true, '{}'::text[], true)
  ) as t(subject, name, tbl, col, purge, omit, exported)
  ) as t(subject, name, tbl, col, purge, omit, exported)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.knowledge_collection_readable (
  collection_id uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select exists (
    select 1 from "better_supabase"."knowledge_collections" c
    where c."id" = knowledge_collection_readable.collection_id
      and (c."organization_id" is null or coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', c."organization_id", 'ai.read'), false))
      and (c."visibility" = 'automatic'
        or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (c."organization_id" is not null and coalesce(better_supabase.can('tenant', c."organization_id", 'ai.admin'), false)))
        or exists (
          select 1 from "better_supabase"."knowledge_collection_grants" x
          where x."collection_id" = c."id" and (x."user_id" = auth.uid() or (x."team_id" is not null and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id" = x."team_id" and tm."user_id" = auth.uid())))
        ))
  )
$function$;

CREATE OR REPLACE FUNCTION better_supabase.memory_create (
  tenant           uuid,
  path             text,
  content          text,
  ns               jsonb   DEFAULT '{}'::jsonb,
  expected_version integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_scope text;
  v_agent uuid;
  v_chat uuid;
  v_project uuid;
  v_subject_type text;
  v_subject_id text;
  v_private boolean;
  v_owner uuid;
  v_row "better_supabase"."memories"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  v_scope := coalesce(memory_create.ns ->> 'scope', 'user');
  v_agent := (memory_create.ns ->> 'agent_id')::uuid;
  v_chat := (memory_create.ns ->> 'chat_id')::uuid;
  v_project := (memory_create.ns ->> 'project_id')::uuid;
  v_subject_type := nullif(memory_create.ns ->> 'subject_type', '');
  v_subject_id := nullif(memory_create.ns ->> 'subject_id', '');
  v_private := coalesce((memory_create.ns ->> 'private')::boolean, false);
  v_owner := case when v_scope in ('organization', 'record') and not v_private then null when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then (memory_create.ns ->> 'owner_id')::uuid else auth.uid() end;
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and (auth.uid() is null or not coalesce(better_supabase.can('tenant', memory_create.tenant, 'ai.read'), false)) then
    raise exception 'you may not use memory here' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if v_scope not in ('user', 'agent', 'chat', 'project', 'organization', 'record')
    or (v_scope = 'agent') <> (v_agent is not null)
    or (v_scope = 'chat') <> (v_chat is not null)
    or (v_scope = 'project') <> (v_project is not null)
    or (v_scope = 'record') <> (v_subject_id is not null)
    or (v_subject_id is not null) <> (v_subject_type is not null)
    or (v_owner is null and (v_scope not in ('organization', 'record') or v_private)) then
    raise exception 'ns % is not a memory namespace', memory_create.ns using errcode = '22023', hint = 'MEMORY_NAMESPACE';
  end if;
  if v_owner is null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', memory_create.tenant, 'ai.admin'), false)) then
    raise exception 'only admins change organization and record memory' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if memory_create.path is null or length(memory_create.path) > 500 or memory_create.path !~ '^/memories(/[A-Za-z0-9._ -]+)*$' or memory_create.path ~ '(^|/)[.]{1,2}(/|$)' then
    raise exception '% is not a path under /memories', memory_create.path using errcode = '22023', hint = 'MEMORY_PATH';
  end if;
  if length(memory_create.content) > 100000 then
    raise exception 'memory content is limited to % characters', 100000 using errcode = '22023', hint = 'MEMORY_TOO_LARGE';
  end if;
  select * into v_row from "better_supabase"."memories" x
  where x."organization_id" = memory_create.tenant and x."owner_id" is not distinct from v_owner and x."scope" = v_scope and x."agent_id" is not distinct from v_agent and x."chat_id" is not distinct from v_chat and x."project_id" is not distinct from v_project and x."subject_type" is not distinct from v_subject_type and x."subject_id" is not distinct from v_subject_id and x."superseded_by" is null and x."deleted_at" is null and x."path" = memory_create.path
  for update;
  if found then
    if memory_create.expected_version is not null and memory_create.expected_version <> v_row."version" then
      raise exception '% changed since version %', memory_create.path, memory_create.expected_version using errcode = '40001', hint = 'MEMORY_CONFLICT';
    end if;
    update "better_supabase"."memories" x set "content" = memory_create.content, "version" = x."version" + 1, "embedding" = null, "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  else
    if coalesce(memory_create.expected_version, 0) <> 0 then
      raise exception '% not found', memory_create.path using errcode = 'P0002', hint = 'MEMORY_NOT_FOUND';
    end if;
    insert into "better_supabase"."memories" ("organization_id", "owner_id", "scope", "agent_id", "chat_id", "project_id", "subject_type", "subject_id", "kind", "path", "content")
    values (memory_create.tenant, v_owner, v_scope, v_agent, v_chat, v_project, v_subject_type, v_subject_id, 'core', memory_create.path, memory_create.content)
    returning * into v_row;
  end if;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'scope', v_row."scope", 'agent_id', v_row."agent_id", 'chat_id', v_row."chat_id", 'project_id', v_row."project_id", 'kind', v_row."kind", 'path', v_row."path", 'content', v_row."content", 'version', v_row."version", 'embedding_model', v_row."embedding_model", 'source_message_id', v_row."source_message_id", 'subject_type', v_row."subject_type", 'subject_id', v_row."subject_id", 'category', v_row."category", 'confidence', v_row."confidence", 'expires_at', v_row."expires_at", 'use_count', v_row."use_count", 'last_used_at', v_row."last_used_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.memory_delete (
  tenant uuid,
  path   text,
  ns     jsonb DEFAULT '{}'::jsonb
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_scope text;
  v_agent uuid;
  v_chat uuid;
  v_project uuid;
  v_subject_type text;
  v_subject_id text;
  v_private boolean;
  v_owner uuid;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  v_scope := coalesce(memory_delete.ns ->> 'scope', 'user');
  v_agent := (memory_delete.ns ->> 'agent_id')::uuid;
  v_chat := (memory_delete.ns ->> 'chat_id')::uuid;
  v_project := (memory_delete.ns ->> 'project_id')::uuid;
  v_subject_type := nullif(memory_delete.ns ->> 'subject_type', '');
  v_subject_id := nullif(memory_delete.ns ->> 'subject_id', '');
  v_private := coalesce((memory_delete.ns ->> 'private')::boolean, false);
  v_owner := case when v_scope in ('organization', 'record') and not v_private then null when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then (memory_delete.ns ->> 'owner_id')::uuid else auth.uid() end;
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and (auth.uid() is null or not coalesce(better_supabase.can('tenant', memory_delete.tenant, 'ai.read'), false)) then
    raise exception 'you may not use memory here' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if v_scope not in ('user', 'agent', 'chat', 'project', 'organization', 'record')
    or (v_scope = 'agent') <> (v_agent is not null)
    or (v_scope = 'chat') <> (v_chat is not null)
    or (v_scope = 'project') <> (v_project is not null)
    or (v_scope = 'record') <> (v_subject_id is not null)
    or (v_subject_id is not null) <> (v_subject_type is not null)
    or (v_owner is null and (v_scope not in ('organization', 'record') or v_private)) then
    raise exception 'ns % is not a memory namespace', memory_delete.ns using errcode = '22023', hint = 'MEMORY_NAMESPACE';
  end if;
  if v_owner is null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', memory_delete.tenant, 'ai.admin'), false)) then
    raise exception 'only admins change organization and record memory' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if memory_delete.path is null or length(memory_delete.path) > 500 or memory_delete.path !~ '^/memories(/[A-Za-z0-9._ -]+)*$' or memory_delete.path ~ '(^|/)[.]{1,2}(/|$)' then
    raise exception '% is not a path under /memories', memory_delete.path using errcode = '22023', hint = 'MEMORY_PATH';
  end if;
  update "better_supabase"."memories" x set "deleted_at" = now(), "updated_at" = now()
  where x."organization_id" = memory_delete.tenant and x."owner_id" is not distinct from v_owner and x."scope" = v_scope and x."agent_id" is not distinct from v_agent and x."chat_id" is not distinct from v_chat and x."project_id" is not distinct from v_project and x."subject_type" is not distinct from v_subject_type and x."subject_id" is not distinct from v_subject_id and x."superseded_by" is null and x."deleted_at" is null
    and (x."path" = memory_delete.path or x."path" like replace(replace(memory_delete.path, '_', '\_'), '%', '\%') || '/%');
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.memory_forget (
  memory_id     uuid,
  superseded_by uuid DEFAULT NULL::uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."memories"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."memories" x where x."id" = memory_forget.memory_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."owner_id" = auth.uid(), false) or (v_row."owner_id" is null and coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai.admin'), false))) then
    return false;
  end if;
  if memory_forget.superseded_by is null then
    update "better_supabase"."memories" x set "deleted_at" = coalesce(x."deleted_at", now()), "updated_at" = now() where x."id" = v_row."id";
  else
    update "better_supabase"."memories" x set "superseded_by" = memory_forget.superseded_by, "updated_at" = now() where x."id" = v_row."id";
  end if;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.memory_insert (
  tenant      uuid,
  path        text,
  insert_line integer,
  insert_text text,
  ns          jsonb   DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_scope text;
  v_agent uuid;
  v_chat uuid;
  v_project uuid;
  v_subject_type text;
  v_subject_id text;
  v_private boolean;
  v_owner uuid;
  v_row "better_supabase"."memories"%rowtype;
  v_lines text[];
  v_content text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  v_scope := coalesce(memory_insert.ns ->> 'scope', 'user');
  v_agent := (memory_insert.ns ->> 'agent_id')::uuid;
  v_chat := (memory_insert.ns ->> 'chat_id')::uuid;
  v_project := (memory_insert.ns ->> 'project_id')::uuid;
  v_subject_type := nullif(memory_insert.ns ->> 'subject_type', '');
  v_subject_id := nullif(memory_insert.ns ->> 'subject_id', '');
  v_private := coalesce((memory_insert.ns ->> 'private')::boolean, false);
  v_owner := case when v_scope in ('organization', 'record') and not v_private then null when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then (memory_insert.ns ->> 'owner_id')::uuid else auth.uid() end;
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and (auth.uid() is null or not coalesce(better_supabase.can('tenant', memory_insert.tenant, 'ai.read'), false)) then
    raise exception 'you may not use memory here' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if v_scope not in ('user', 'agent', 'chat', 'project', 'organization', 'record')
    or (v_scope = 'agent') <> (v_agent is not null)
    or (v_scope = 'chat') <> (v_chat is not null)
    or (v_scope = 'project') <> (v_project is not null)
    or (v_scope = 'record') <> (v_subject_id is not null)
    or (v_subject_id is not null) <> (v_subject_type is not null)
    or (v_owner is null and (v_scope not in ('organization', 'record') or v_private)) then
    raise exception 'ns % is not a memory namespace', memory_insert.ns using errcode = '22023', hint = 'MEMORY_NAMESPACE';
  end if;
  if v_owner is null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', memory_insert.tenant, 'ai.admin'), false)) then
    raise exception 'only admins change organization and record memory' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if memory_insert.path is null or length(memory_insert.path) > 500 or memory_insert.path !~ '^/memories(/[A-Za-z0-9._ -]+)*$' or memory_insert.path ~ '(^|/)[.]{1,2}(/|$)' then
    raise exception '% is not a path under /memories', memory_insert.path using errcode = '22023', hint = 'MEMORY_PATH';
  end if;
  select * into v_row from "better_supabase"."memories" x
  where x."organization_id" = memory_insert.tenant and x."owner_id" is not distinct from v_owner and x."scope" = v_scope and x."agent_id" is not distinct from v_agent and x."chat_id" is not distinct from v_chat and x."project_id" is not distinct from v_project and x."subject_type" is not distinct from v_subject_type and x."subject_id" is not distinct from v_subject_id and x."superseded_by" is null and x."deleted_at" is null and x."path" = memory_insert.path
  for update;
  if not found then
    raise exception '% not found', memory_insert.path using errcode = 'P0002', hint = 'MEMORY_NOT_FOUND';
  end if;
  v_lines := case when v_row."content" = '' then '{}'::text[] else string_to_array(v_row."content", E'\n') end;
  if memory_insert.insert_line < 0 or memory_insert.insert_line > coalesce(array_length(v_lines, 1), 0) then
    raise exception 'line % is outside the file', memory_insert.insert_line using errcode = '22023', hint = 'MEMORY_LINE';
  end if;
  v_content := array_to_string(v_lines[1:memory_insert.insert_line] || string_to_array(coalesce(memory_insert.insert_text, ''), E'\n') || v_lines[memory_insert.insert_line + 1:], E'\n');
  if length(v_content) > 100000 then
    raise exception 'memory content is limited to % characters', 100000 using errcode = '22023', hint = 'MEMORY_TOO_LARGE';
  end if;
  update "better_supabase"."memories" x set "content" = v_content, "version" = x."version" + 1, "embedding" = null, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'scope', v_row."scope", 'agent_id', v_row."agent_id", 'chat_id', v_row."chat_id", 'project_id', v_row."project_id", 'kind', v_row."kind", 'path', v_row."path", 'content', v_row."content", 'version', v_row."version", 'embedding_model', v_row."embedding_model", 'source_message_id', v_row."source_message_id", 'subject_type', v_row."subject_type", 'subject_id', v_row."subject_id", 'category', v_row."category", 'confidence', v_row."confidence", 'expires_at', v_row."expires_at", 'use_count', v_row."use_count", 'last_used_at', v_row."last_used_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.memory_list (
  tenant   uuid,
  ns       jsonb   DEFAULT '{}'::jsonb,
  kind     text    DEFAULT 'core'::text,
  max_rows integer DEFAULT 200
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_scope text;
  v_agent uuid;
  v_chat uuid;
  v_project uuid;
  v_subject_type text;
  v_subject_id text;
  v_private boolean;
  v_owner uuid;
  v_rows jsonb;
begin
  v_scope := coalesce(memory_list.ns ->> 'scope', 'user');
  v_agent := (memory_list.ns ->> 'agent_id')::uuid;
  v_chat := (memory_list.ns ->> 'chat_id')::uuid;
  v_project := (memory_list.ns ->> 'project_id')::uuid;
  v_subject_type := nullif(memory_list.ns ->> 'subject_type', '');
  v_subject_id := nullif(memory_list.ns ->> 'subject_id', '');
  v_private := coalesce((memory_list.ns ->> 'private')::boolean, false);
  v_owner := case when v_scope in ('organization', 'record') and not v_private then null when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then (memory_list.ns ->> 'owner_id')::uuid else auth.uid() end;
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and (auth.uid() is null or not coalesce(better_supabase.can('tenant', memory_list.tenant, 'ai.read'), false)) then
    raise exception 'you may not use memory here' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if v_scope not in ('user', 'agent', 'chat', 'project', 'organization', 'record')
    or (v_scope = 'agent') <> (v_agent is not null)
    or (v_scope = 'chat') <> (v_chat is not null)
    or (v_scope = 'project') <> (v_project is not null)
    or (v_scope = 'record') <> (v_subject_id is not null)
    or (v_subject_id is not null) <> (v_subject_type is not null)
    or (v_owner is null and (v_scope not in ('organization', 'record') or v_private)) then
    raise exception 'ns % is not a memory namespace', memory_list.ns using errcode = '22023', hint = 'MEMORY_NAMESPACE';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organization_id', x."organization_id", 'owner_id', x."owner_id", 'scope', x."scope", 'agent_id', x."agent_id", 'chat_id', x."chat_id", 'project_id', x."project_id", 'kind', x."kind", 'path', x."path", 'content', x."content", 'version', x."version", 'embedding_model', x."embedding_model", 'source_message_id', x."source_message_id", 'subject_type', x."subject_type", 'subject_id', x."subject_id", 'category', x."category", 'confidence', x."confidence", 'expires_at', x."expires_at", 'use_count', x."use_count", 'last_used_at', x."last_used_at", 'created_at', x."created_at", 'updated_at', x."updated_at") order by x."path", x."created_at" desc), '[]') into v_rows
  from (
    select * from "better_supabase"."memories" y
    where y."organization_id" = memory_list.tenant and y."owner_id" is not distinct from v_owner and y."scope" = v_scope and y."agent_id" is not distinct from v_agent and y."chat_id" is not distinct from v_chat and y."project_id" is not distinct from v_project and y."subject_type" is not distinct from v_subject_type and y."subject_id" is not distinct from v_subject_id and y."superseded_by" is null and y."deleted_at" is null and (y."expires_at" is null or y."expires_at" > now()) and y."kind" = memory_list.kind
    order by y."path", y."created_at" desc
    limit least(greatest(memory_list.max_rows, 1), 1000)
  ) x;
  return v_rows;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.memory_rename (
  tenant   uuid,
  old_path text,
  new_path text,
  ns       jsonb DEFAULT '{}'::jsonb
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_scope text;
  v_agent uuid;
  v_chat uuid;
  v_project uuid;
  v_subject_type text;
  v_subject_id text;
  v_private boolean;
  v_owner uuid;
  v_count integer;
  v_prefix text := replace(replace(memory_rename.old_path, '_', '\_'), '%', '\%') || '/%';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  v_scope := coalesce(memory_rename.ns ->> 'scope', 'user');
  v_agent := (memory_rename.ns ->> 'agent_id')::uuid;
  v_chat := (memory_rename.ns ->> 'chat_id')::uuid;
  v_project := (memory_rename.ns ->> 'project_id')::uuid;
  v_subject_type := nullif(memory_rename.ns ->> 'subject_type', '');
  v_subject_id := nullif(memory_rename.ns ->> 'subject_id', '');
  v_private := coalesce((memory_rename.ns ->> 'private')::boolean, false);
  v_owner := case when v_scope in ('organization', 'record') and not v_private then null when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then (memory_rename.ns ->> 'owner_id')::uuid else auth.uid() end;
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and (auth.uid() is null or not coalesce(better_supabase.can('tenant', memory_rename.tenant, 'ai.read'), false)) then
    raise exception 'you may not use memory here' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if v_scope not in ('user', 'agent', 'chat', 'project', 'organization', 'record')
    or (v_scope = 'agent') <> (v_agent is not null)
    or (v_scope = 'chat') <> (v_chat is not null)
    or (v_scope = 'project') <> (v_project is not null)
    or (v_scope = 'record') <> (v_subject_id is not null)
    or (v_subject_id is not null) <> (v_subject_type is not null)
    or (v_owner is null and (v_scope not in ('organization', 'record') or v_private)) then
    raise exception 'ns % is not a memory namespace', memory_rename.ns using errcode = '22023', hint = 'MEMORY_NAMESPACE';
  end if;
  if v_owner is null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', memory_rename.tenant, 'ai.admin'), false)) then
    raise exception 'only admins change organization and record memory' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if memory_rename.old_path is null or length(memory_rename.old_path) > 500 or memory_rename.old_path !~ '^/memories(/[A-Za-z0-9._ -]+)*$' or memory_rename.old_path ~ '(^|/)[.]{1,2}(/|$)' then
    raise exception '% is not a path under /memories', memory_rename.old_path using errcode = '22023', hint = 'MEMORY_PATH';
  end if;
  if memory_rename.new_path is null or length(memory_rename.new_path) > 500 or memory_rename.new_path !~ '^/memories(/[A-Za-z0-9._ -]+)*$' or memory_rename.new_path ~ '(^|/)[.]{1,2}(/|$)' then
    raise exception '% is not a path under /memories', memory_rename.new_path using errcode = '22023', hint = 'MEMORY_PATH';
  end if;
  if memory_rename.new_path = memory_rename.old_path or memory_rename.new_path like v_prefix then
    raise exception 'cannot move % into itself', memory_rename.old_path using errcode = '22023', hint = 'MEMORY_PATH';
  end if;
  if exists (
    select 1 from "better_supabase"."memories" x
    where x."organization_id" = memory_rename.tenant and x."owner_id" is not distinct from v_owner and x."scope" = v_scope and x."agent_id" is not distinct from v_agent and x."chat_id" is not distinct from v_chat and x."project_id" is not distinct from v_project and x."subject_type" is not distinct from v_subject_type and x."subject_id" is not distinct from v_subject_id and x."superseded_by" is null and x."deleted_at" is null
      and (x."path" = memory_rename.new_path or x."path" like replace(replace(memory_rename.new_path, '_', '\_'), '%', '\%') || '/%')
  ) then
    raise exception '% already exists', memory_rename.new_path using errcode = '23505', hint = 'MEMORY_EXISTS';
  end if;
  update "better_supabase"."memories" x set
    "path" = memory_rename.new_path || substr(x."path", length(memory_rename.old_path) + 1),
    "version" = x."version" + 1, "updated_at" = now()
  where x."organization_id" = memory_rename.tenant and x."owner_id" is not distinct from v_owner and x."scope" = v_scope and x."agent_id" is not distinct from v_agent and x."chat_id" is not distinct from v_chat and x."project_id" is not distinct from v_project and x."subject_type" is not distinct from v_subject_type and x."subject_id" is not distinct from v_subject_id and x."superseded_by" is null and x."deleted_at" is null
    and (x."path" = memory_rename.old_path or x."path" like v_prefix);
  get diagnostics v_count = row_count;
  if v_count = 0 then
    raise exception '% not found', memory_rename.old_path using errcode = 'P0002', hint = 'MEMORY_NOT_FOUND';
  end if;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.memory_restore (
  memory_id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."memories"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."memories" x where x."id" = memory_restore.memory_id and x."deleted_at" is not null;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."owner_id" = auth.uid(), false) or (v_row."owner_id" is null and coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai.admin'), false))) then
    return false;
  end if;
  update "better_supabase"."memories" x set "deleted_at" = null, "updated_at" = now() where x."id" = v_row."id";
  return true;
exception when unique_violation then
  raise exception '% already exists', v_row."path" using errcode = '23505', hint = 'MEMORY_EXISTS';
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.memory_save (
  tenant            uuid,
  content           text,
  ns                jsonb                    DEFAULT '{}'::jsonb,
  embedding         extensions.vector        DEFAULT NULL::extensions.vector,
  model             text                     DEFAULT NULL::text,
  source_message_id text                     DEFAULT NULL::text,
  category          text                     DEFAULT NULL::text,
  confidence        real                     DEFAULT NULL::real,
  expires_at        timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_scope text;
  v_agent uuid;
  v_chat uuid;
  v_project uuid;
  v_subject_type text;
  v_subject_id text;
  v_private boolean;
  v_owner uuid;
  v_row "better_supabase"."memories"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  v_scope := coalesce(memory_save.ns ->> 'scope', 'user');
  v_agent := (memory_save.ns ->> 'agent_id')::uuid;
  v_chat := (memory_save.ns ->> 'chat_id')::uuid;
  v_project := (memory_save.ns ->> 'project_id')::uuid;
  v_subject_type := nullif(memory_save.ns ->> 'subject_type', '');
  v_subject_id := nullif(memory_save.ns ->> 'subject_id', '');
  v_private := coalesce((memory_save.ns ->> 'private')::boolean, false);
  v_owner := case when v_scope in ('organization', 'record') and not v_private then null when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then (memory_save.ns ->> 'owner_id')::uuid else auth.uid() end;
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and (auth.uid() is null or not coalesce(better_supabase.can('tenant', memory_save.tenant, 'ai.read'), false)) then
    raise exception 'you may not use memory here' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if v_scope not in ('user', 'agent', 'chat', 'project', 'organization', 'record')
    or (v_scope = 'agent') <> (v_agent is not null)
    or (v_scope = 'chat') <> (v_chat is not null)
    or (v_scope = 'project') <> (v_project is not null)
    or (v_scope = 'record') <> (v_subject_id is not null)
    or (v_subject_id is not null) <> (v_subject_type is not null)
    or (v_owner is null and (v_scope not in ('organization', 'record') or v_private)) then
    raise exception 'ns % is not a memory namespace', memory_save.ns using errcode = '22023', hint = 'MEMORY_NAMESPACE';
  end if;
  if v_owner is null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', memory_save.tenant, 'ai.admin'), false)) then
    raise exception 'only admins change organization and record memory' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if coalesce(length(memory_save.content), 0) = 0 then
    raise exception 'memory content is empty' using errcode = '22023', hint = 'MEMORY_EMPTY';
  end if;
  if length(memory_save.content) > 100000 then
    raise exception 'memory content is limited to % characters', 100000 using errcode = '22023', hint = 'MEMORY_TOO_LARGE';
  end if;
  if memory_save.confidence is not null and not memory_save.confidence between 0 and 1 then
    raise exception 'confidence % is not between 0 and 1', memory_save.confidence using errcode = '22023', hint = 'MEMORY_CONFIDENCE';
  end if;
  if memory_save.category is not null and memory_save.category !~ '^[a-z0-9][a-z0-9_-]*$' then
    raise exception 'category % is not a lowercase slug', memory_save.category using errcode = '22023', hint = 'MEMORY_CATEGORY';
  end if;
  insert into "better_supabase"."memories" ("organization_id", "owner_id", "scope", "agent_id", "chat_id", "project_id", "subject_type", "subject_id", "kind", "content", "embedding", "embedding_model", "source_message_id", "category", "confidence", "expires_at")
  values (memory_save.tenant, v_owner, v_scope, v_agent, v_chat, v_project, v_subject_type, v_subject_id, 'archival', memory_save.content, memory_save.embedding, memory_save.model, memory_save.source_message_id, memory_save.category, memory_save.confidence, memory_save.expires_at)
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'scope', v_row."scope", 'agent_id', v_row."agent_id", 'chat_id', v_row."chat_id", 'project_id', v_row."project_id", 'kind', v_row."kind", 'path', v_row."path", 'content', v_row."content", 'version', v_row."version", 'embedding_model', v_row."embedding_model", 'source_message_id', v_row."source_message_id", 'subject_type', v_row."subject_type", 'subject_id', v_row."subject_id", 'category', v_row."category", 'confidence', v_row."confidence", 'expires_at', v_row."expires_at", 'use_count', v_row."use_count", 'last_used_at', v_row."last_used_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.memory_search (
  tenant          uuid,
  query_embedding extensions.vector DEFAULT NULL::extensions.vector,
  query_text      text              DEFAULT NULL::text,
  ns              jsonb             DEFAULT '{}'::jsonb,
  k               integer           DEFAULT 8
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_scope text;
  v_agent uuid;
  v_chat uuid;
  v_project uuid;
  v_subject_type text;
  v_subject_id text;
  v_private boolean;
  v_owner uuid;
  v_rows jsonb;
  v_candidates integer := least(greatest(memory_search.k, 1) * 4, 400);
  v_scan text := current_setting('hnsw.iterative_scan', true);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  v_scope := coalesce(memory_search.ns ->> 'scope', 'user');
  v_agent := (memory_search.ns ->> 'agent_id')::uuid;
  v_chat := (memory_search.ns ->> 'chat_id')::uuid;
  v_project := (memory_search.ns ->> 'project_id')::uuid;
  v_subject_type := nullif(memory_search.ns ->> 'subject_type', '');
  v_subject_id := nullif(memory_search.ns ->> 'subject_id', '');
  v_private := coalesce((memory_search.ns ->> 'private')::boolean, false);
  v_owner := case when v_scope in ('organization', 'record') and not v_private then null when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then (memory_search.ns ->> 'owner_id')::uuid else auth.uid() end;
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and (auth.uid() is null or not coalesce(better_supabase.can('tenant', memory_search.tenant, 'ai.read'), false)) then
    raise exception 'you may not use memory here' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if v_scope not in ('user', 'agent', 'chat', 'project', 'organization', 'record')
    or (v_scope = 'agent') <> (v_agent is not null)
    or (v_scope = 'chat') <> (v_chat is not null)
    or (v_scope = 'project') <> (v_project is not null)
    or (v_scope = 'record') <> (v_subject_id is not null)
    or (v_subject_id is not null) <> (v_subject_type is not null)
    or (v_owner is null and (v_scope not in ('organization', 'record') or v_private)) then
    raise exception 'ns % is not a memory namespace', memory_search.ns using errcode = '22023', hint = 'MEMORY_NAMESPACE';
  end if;
  perform set_config('hnsw.iterative_scan', 'relaxed_order', true);
  with scoped as materialized (
    select x."id" as id from "better_supabase"."memories" x
    where x."organization_id" = memory_search.tenant and x."owner_id" is not distinct from v_owner and x."scope" = v_scope and x."agent_id" is not distinct from v_agent and x."chat_id" is not distinct from v_chat and x."project_id" is not distinct from v_project and x."subject_type" is not distinct from v_subject_type and x."subject_id" is not distinct from v_subject_id and x."superseded_by" is null and x."deleted_at" is null and (x."expires_at" is null or x."expires_at" > now()) and x."kind" = 'archival'
  ),
  vector_hits as materialized (
    select t."id" as id, t."embedding" operator(extensions.<=>) memory_search.query_embedding as distance
    from "better_supabase"."memories" t
    where memory_search.query_embedding is not null and t."embedding" is not null and t."id" in (select scoped.id from scoped)
    order by t."embedding" operator(extensions.<=>) memory_search.query_embedding
    limit v_candidates
  ),
  vector_ranked as (
    select h.id, h.distance, row_number() over (order by h.distance) as rank from vector_hits h
  ),
  text_ranked as (
    select t."id" as id, row_number() over (order by ts_rank_cd(t."tsv", q) desc) as rank
    from "better_supabase"."memories" t, websearch_to_tsquery('simple'::regconfig, memory_search.query_text) q
    where memory_search.query_text is not null and t."tsv" @@ q and t."id" in (select scoped.id from scoped)
    limit v_candidates
  ),
  fused as materialized (
    select r.id, r.distance, r.score * coalesce(t."confidence", 1) as score
    from (
      select coalesce(v.id, x.id) as id, v.distance,
        coalesce(1.0 / (60 + v.rank), 0) + coalesce(1.0 / (60 + x.rank), 0) as score
      from vector_ranked v full join text_ranked x on x.id = v.id
    ) r join "better_supabase"."memories" t on t."id" = r.id
    order by score desc
    limit least(greatest(memory_search.k, 1), 100)
  ),
  used as (
    update "better_supabase"."memories" t set "use_count" = t."use_count" + 1, "last_used_at" = now()
    from fused f where t."id" = f.id
  )
  select coalesce(jsonb_agg(jsonb_build_object('id', t."id", 'organization_id', t."organization_id", 'owner_id', t."owner_id", 'scope', t."scope", 'agent_id', t."agent_id", 'chat_id', t."chat_id", 'project_id', t."project_id", 'kind', t."kind", 'path', t."path", 'content', t."content", 'version', t."version", 'embedding_model', t."embedding_model", 'source_message_id', t."source_message_id", 'subject_type', t."subject_type", 'subject_id', t."subject_id", 'category', t."category", 'confidence', t."confidence", 'expires_at', t."expires_at", 'use_count', t."use_count", 'last_used_at', t."last_used_at", 'created_at', t."created_at", 'updated_at', t."updated_at") || jsonb_build_object('score', f.score, 'similarity', 1 - f.distance) order by f.score desc), '[]')
  into v_rows
  from fused f join "better_supabase"."memories" t on t."id" = f.id;
  perform set_config('hnsw.iterative_scan', coalesce(nullif(v_scan, ''), 'off'), true);
  return v_rows;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.memory_str_replace (
  tenant   uuid,
  path     text,
  old_text text,
  new_text text,
  ns       jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_scope text;
  v_agent uuid;
  v_chat uuid;
  v_project uuid;
  v_subject_type text;
  v_subject_id text;
  v_private boolean;
  v_owner uuid;
  v_row "better_supabase"."memories"%rowtype;
  v_matches integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  v_scope := coalesce(memory_str_replace.ns ->> 'scope', 'user');
  v_agent := (memory_str_replace.ns ->> 'agent_id')::uuid;
  v_chat := (memory_str_replace.ns ->> 'chat_id')::uuid;
  v_project := (memory_str_replace.ns ->> 'project_id')::uuid;
  v_subject_type := nullif(memory_str_replace.ns ->> 'subject_type', '');
  v_subject_id := nullif(memory_str_replace.ns ->> 'subject_id', '');
  v_private := coalesce((memory_str_replace.ns ->> 'private')::boolean, false);
  v_owner := case when v_scope in ('organization', 'record') and not v_private then null when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then (memory_str_replace.ns ->> 'owner_id')::uuid else auth.uid() end;
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and (auth.uid() is null or not coalesce(better_supabase.can('tenant', memory_str_replace.tenant, 'ai.read'), false)) then
    raise exception 'you may not use memory here' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if v_scope not in ('user', 'agent', 'chat', 'project', 'organization', 'record')
    or (v_scope = 'agent') <> (v_agent is not null)
    or (v_scope = 'chat') <> (v_chat is not null)
    or (v_scope = 'project') <> (v_project is not null)
    or (v_scope = 'record') <> (v_subject_id is not null)
    or (v_subject_id is not null) <> (v_subject_type is not null)
    or (v_owner is null and (v_scope not in ('organization', 'record') or v_private)) then
    raise exception 'ns % is not a memory namespace', memory_str_replace.ns using errcode = '22023', hint = 'MEMORY_NAMESPACE';
  end if;
  if v_owner is null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', memory_str_replace.tenant, 'ai.admin'), false)) then
    raise exception 'only admins change organization and record memory' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if memory_str_replace.path is null or length(memory_str_replace.path) > 500 or memory_str_replace.path !~ '^/memories(/[A-Za-z0-9._ -]+)*$' or memory_str_replace.path ~ '(^|/)[.]{1,2}(/|$)' then
    raise exception '% is not a path under /memories', memory_str_replace.path using errcode = '22023', hint = 'MEMORY_PATH';
  end if;
  select * into v_row from "better_supabase"."memories" x
  where x."organization_id" = memory_str_replace.tenant and x."owner_id" is not distinct from v_owner and x."scope" = v_scope and x."agent_id" is not distinct from v_agent and x."chat_id" is not distinct from v_chat and x."project_id" is not distinct from v_project and x."subject_type" is not distinct from v_subject_type and x."subject_id" is not distinct from v_subject_id and x."superseded_by" is null and x."deleted_at" is null and x."path" = memory_str_replace.path
  for update;
  if not found then
    raise exception '% not found', memory_str_replace.path using errcode = 'P0002', hint = 'MEMORY_NOT_FOUND';
  end if;
  if coalesce(length(memory_str_replace.old_text), 0) = 0 then
    raise exception 'old_text is empty' using errcode = '22023', hint = 'MEMORY_NO_MATCH';
  end if;
  v_matches := (length(v_row."content") - length(replace(v_row."content", memory_str_replace.old_text, ''))) / length(memory_str_replace.old_text);
  if v_matches = 0 then
    raise exception 'old_text does not appear in %', memory_str_replace.path using errcode = '22023', hint = 'MEMORY_NO_MATCH';
  elsif v_matches > 1 then
    raise exception 'old_text appears % times in %', v_matches, memory_str_replace.path using errcode = '22023', hint = 'MEMORY_AMBIGUOUS';
  end if;
  if length(replace(v_row."content", memory_str_replace.old_text, coalesce(memory_str_replace.new_text, ''))) > 100000 then
    raise exception 'memory content is limited to % characters', 100000 using errcode = '22023', hint = 'MEMORY_TOO_LARGE';
  end if;
  update "better_supabase"."memories" x set
    "content" = replace(x."content", memory_str_replace.old_text, coalesce(memory_str_replace.new_text, '')),
    "version" = x."version" + 1, "embedding" = null, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'scope', v_row."scope", 'agent_id', v_row."agent_id", 'chat_id', v_row."chat_id", 'project_id', v_row."project_id", 'kind', v_row."kind", 'path', v_row."path", 'content', v_row."content", 'version', v_row."version", 'embedding_model', v_row."embedding_model", 'source_message_id', v_row."source_message_id", 'subject_type', v_row."subject_type", 'subject_id', v_row."subject_id", 'category', v_row."category", 'confidence', v_row."confidence", 'expires_at', v_row."expires_at", 'use_count', v_row."use_count", 'last_used_at', v_row."last_used_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.memory_view (
  tenant uuid,
  path   text  DEFAULT '/memories'::text,
  ns     jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_scope text;
  v_agent uuid;
  v_chat uuid;
  v_project uuid;
  v_subject_type text;
  v_subject_id text;
  v_private boolean;
  v_owner uuid;
  v_row "better_supabase"."memories"%rowtype;
  v_entries jsonb;
begin
  v_scope := coalesce(memory_view.ns ->> 'scope', 'user');
  v_agent := (memory_view.ns ->> 'agent_id')::uuid;
  v_chat := (memory_view.ns ->> 'chat_id')::uuid;
  v_project := (memory_view.ns ->> 'project_id')::uuid;
  v_subject_type := nullif(memory_view.ns ->> 'subject_type', '');
  v_subject_id := nullif(memory_view.ns ->> 'subject_id', '');
  v_private := coalesce((memory_view.ns ->> 'private')::boolean, false);
  v_owner := case when v_scope in ('organization', 'record') and not v_private then null when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then (memory_view.ns ->> 'owner_id')::uuid else auth.uid() end;
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and (auth.uid() is null or not coalesce(better_supabase.can('tenant', memory_view.tenant, 'ai.read'), false)) then
    raise exception 'you may not use memory here' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if v_scope not in ('user', 'agent', 'chat', 'project', 'organization', 'record')
    or (v_scope = 'agent') <> (v_agent is not null)
    or (v_scope = 'chat') <> (v_chat is not null)
    or (v_scope = 'project') <> (v_project is not null)
    or (v_scope = 'record') <> (v_subject_id is not null)
    or (v_subject_id is not null) <> (v_subject_type is not null)
    or (v_owner is null and (v_scope not in ('organization', 'record') or v_private)) then
    raise exception 'ns % is not a memory namespace', memory_view.ns using errcode = '22023', hint = 'MEMORY_NAMESPACE';
  end if;
  if memory_view.path is null or length(memory_view.path) > 500 or memory_view.path !~ '^/memories(/[A-Za-z0-9._ -]+)*$' or memory_view.path ~ '(^|/)[.]{1,2}(/|$)' then
    raise exception '% is not a path under /memories', memory_view.path using errcode = '22023', hint = 'MEMORY_PATH';
  end if;
  select * into v_row from "better_supabase"."memories" x
  where x."organization_id" = memory_view.tenant and x."owner_id" is not distinct from v_owner and x."scope" = v_scope and x."agent_id" is not distinct from v_agent and x."chat_id" is not distinct from v_chat and x."project_id" is not distinct from v_project and x."subject_type" is not distinct from v_subject_type and x."subject_id" is not distinct from v_subject_id and x."superseded_by" is null and x."deleted_at" is null and x."path" = memory_view.path;
  if found then
    return jsonb_build_object('type', 'file', 'path', v_row."path", 'content', v_row."content", 'version', v_row."version", 'updated_at', v_row."updated_at");
  end if;
  select jsonb_agg(jsonb_build_object('path', x."path", 'size', length(x."content"), 'updated_at', x."updated_at") order by x."path")
  into v_entries
  from "better_supabase"."memories" x
  where x."organization_id" = memory_view.tenant and x."owner_id" is not distinct from v_owner and x."scope" = v_scope and x."agent_id" is not distinct from v_agent and x."chat_id" is not distinct from v_chat and x."project_id" is not distinct from v_project and x."subject_type" is not distinct from v_subject_type and x."subject_id" is not distinct from v_subject_id and x."superseded_by" is null and x."deleted_at" is null and x."path" like replace(replace(memory_view.path, '_', '\_'), '%', '\%') || '/%';
  if v_entries is null and memory_view.path <> '/memories' then
    return null;
  end if;
  return jsonb_build_object('type', 'directory', 'path', memory_view.path, 'entries', coalesce(v_entries, '[]'));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_memories (
  retention_days integer DEFAULT 30,
  batch          integer DEFAULT 1000,
  tenant         uuid    DEFAULT NULL::uuid
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_count integer;
begin
  delete from "better_supabase"."memories" x
  where x."id" in (
    select y."id" from "better_supabase"."memories" y
    where (purge_memories.tenant is null or y."organization_id" = purge_memories.tenant)
      and (y."deleted_at" < now() - make_interval(days => greatest(purge_memories.retention_days, 0)) or y."expires_at" < now())
    limit least(greatest(purge_memories.batch, 1), 10000)
  );
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_knowledge_collection_grant (
  collection_id uuid,
  user_id       uuid    DEFAULT NULL::uuid,
  team_id       uuid    DEFAULT NULL::uuid,
  granted       boolean DEFAULT true
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."knowledge_collections"%rowtype;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."knowledge_collections" x where x."id" = set_knowledge_collection_grant.collection_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."organization_id" is not null and coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai.admin'), false))) then
    raise exception 'collection % not found', set_knowledge_collection_grant.collection_id using errcode = 'P0002', hint = 'KNOWLEDGE_COLLECTION_NOT_FOUND';
  end if;
  if (set_knowledge_collection_grant.user_id is null) = (set_knowledge_collection_grant.team_id is null) then
    raise exception 'name a user or a team' using errcode = '22023', hint = 'KNOWLEDGE_GRANT';
  end if;
  if set_knowledge_collection_grant.granted then
    insert into "better_supabase"."knowledge_collection_grants" ("collection_id", "organization_id", "user_id", "team_id")
    values (v_row."id", v_row."organization_id", set_knowledge_collection_grant.user_id, set_knowledge_collection_grant.team_id)
    on conflict do nothing;
  else
    delete from "better_supabase"."knowledge_collection_grants" x
    where x."collection_id" = v_row."id"
      and x."user_id" is not distinct from set_knowledge_collection_grant.user_id
      and x."team_id" is not distinct from set_knowledge_collection_grant.team_id;
  end if;
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$function$;

CREATE INDEX knowledge_collection_grants_tenant_idx ON better_supabase.knowledge_collection_grants USING btree (organization_id)
  WHERE (organization_id IS NOT NULL);

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."memories"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (((owner_id = ( SELECT auth.uid() AS uid)) OR ((owner_id IS NULL) AND
    (organization_id IN ( SELECT better_supabase.tenant_ids_with('ai.read'::text) AS tenant_ids_with)))) AND (deleted_at IS NULL))));

CREATE POLICY "memories_read" ON "better_supabase"."memories"
  FOR SELECT
  TO "authenticated"
  USING
    ((((owner_id = ( SELECT auth.uid() AS uid)) OR ((owner_id IS NULL) AND (organization_id IN ( SELECT better_supabase.tenant_ids_with('ai.read'::text) AS tenant_ids_with)))) AND
    (deleted_at IS NULL)));

REVOKE ALL ON FUNCTION "api"."purge_memories"(integer, integer, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."purge_memories"(integer, integer, uuid) TO "service_role";

REVOKE ALL ON FUNCTION "api"."set_knowledge_collection_grant"(uuid, uuid, uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_knowledge_collection_grant"(uuid, uuid, uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."purge_memories"(integer, integer, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."purge_memories"(integer, integer, uuid) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_knowledge_collection_grant"(uuid, uuid, uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_knowledge_collection_grant"(uuid, uuid, uuid, boolean) TO "authenticated", "service_role";
