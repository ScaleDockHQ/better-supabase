SET local check_function_bodies = off;

DROP POLICY "bsb_tenant_scope_select" ON "better_supabase"."conversations";

DROP POLICY "conversations_read" ON "better_supabase"."conversations";

DROP POLICY "bsb_tenant_scope_select" ON "better_supabase"."inbox_conversations";

DROP POLICY "conversations_read" ON "better_supabase"."inbox_conversations";

DROP FUNCTION "api"."link_inbox_contact"(uuid, uuid);

DROP FUNCTION "api"."person_for_inbox_contact"(uuid, boolean);

DROP FUNCTION "api"."unlink_inbox_contact"(uuid);

DROP FUNCTION "better_supabase"."inbox_contact_ids"();

DROP FUNCTION "better_supabase"."inbox_conversation_allowed"(text, boolean);

CREATE OR REPLACE FUNCTION api.add_person_identity (
  person   uuid,
  channel  text,
  address  text,
  verified boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."add_person_identity"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.find_person_by_identity (
  tenant  uuid,
  channel text,
  address text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."find_person_by_identity"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.list_person_identities (
  person uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_person_identities"($1) $function$;

CREATE OR REPLACE FUNCTION api.remove_person_identity (
  identity uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."remove_person_identity"($1) $function$;

CREATE OR REPLACE FUNCTION better_supabase.add_person_identity (
  person   uuid,
  channel  text,
  address  text,
  verified boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_channel text := nullif(trim(add_person_identity.channel), '');
  v_address text := nullif(trim(add_person_identity.address), '');
  v_holder uuid;
  v_row jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select p."tenant_id" into v_tenant from "better_supabase"."people" p
  where p."id" = add_person_identity.person and p."merged_into" is null;
  if v_tenant is null then
    raise exception 'person not found' using errcode = 'P0002', hint = 'PARTY_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'contacts.write'), false)) then
    raise exception 'not allowed to change companies and people' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  if v_channel is null or v_address is null then
    raise exception 'an identity needs a channel and an address' using errcode = '22023', hint = 'PARTY_IDENTITY_INVALID';
  end if;
  select i."person_id" into v_holder from "better_supabase"."person_identities" i
  where i."tenant_id" = v_tenant and i."channel" = v_channel and i."address" = v_address;
  if v_holder is not null and v_holder <> add_person_identity.person then
    raise exception 'another person has this address' using errcode = '23505', hint = 'PARTY_IDENTITY_TAKEN';
  end if;
  insert into "better_supabase"."person_identities" ("tenant_id", "person_id", "channel", "address", "verified_at")
  values (v_tenant, add_person_identity.person, v_channel, v_address, case when add_person_identity.verified then now() end)
  on conflict do nothing;
  if add_person_identity.verified then
    update "better_supabase"."person_identities" i set "verified_at" = coalesce(i."verified_at", now())
    where i."tenant_id" = v_tenant and i."channel" = v_channel and i."address" = v_address;
  end if;
  select jsonb_build_object('id', i."id", 'tenant_id', i."tenant_id", 'person_id', i."person_id", 'channel', i."channel", 'address', i."address", 'verified_at', i."verified_at", 'created_at', i."created_at") into v_row from "better_supabase"."person_identities" i
  where i."tenant_id" = v_tenant and i."channel" = v_channel and i."address" = v_address;
  return v_row;
end;
$function$;

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
    ('user', 'better_supabase.ai_suggestions', '"better_supabase"."ai_suggestions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.knowledge_documents', '"better_supabase"."knowledge_documents"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.knowledge_collection_grants', '"better_supabase"."knowledge_collection_grants"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.memories', '"better_supabase"."memories"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.memory_message_embeddings', '"better_supabase"."memory_message_embeddings"', 'user_id', true, '{}'::text[], true),
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
    ('user', 'better_supabase.activities', '"better_supabase"."activities"', 'owner_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.quotes', '"better_supabase"."quotes"', 'owner_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.employees', '"better_supabase"."employees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.employee_private_details', '"better_supabase"."employee_private_details"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.moderation_reports', '"better_supabase"."moderation_reports"', 'reporter_id', true, '{}'::text[], true),
    ('user', 'better_supabase.moderation_bans', '"better_supabase"."moderation_bans"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.assets', '"better_supabase"."assets"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.score_models', '"better_supabase"."score_models"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.score_model_versions', '"better_supabase"."score_model_versions"', 'saved_by', true, '{}'::text[], true),
    ('user', 'better_supabase.passes', '"better_supabase"."passes"', 'holder_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.leases', '"better_supabase"."leases"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.expense_reports', '"better_supabase"."expense_reports"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.pledges', '"better_supabase"."pledges"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.donations', '"better_supabase"."donations"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.work_orders', '"better_supabase"."work_orders"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.dispatch_routes', '"better_supabase"."dispatch_routes"', 'technician_id', true, '{}'::text[], true),
    ('user', 'better_supabase.work_order_parts', '"better_supabase"."work_order_parts"', 'recorded_by', true, '{}'::text[], true),
    ('user', 'better_supabase.shipments', '"better_supabase"."shipments"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.contracts', '"better_supabase"."contracts"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.control_evidence', '"better_supabase"."control_evidence"', 'collected_by', true, '{}'::text[], true),
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
    ('user', 'better_supabase.post_boards', '"better_supabase"."post_boards"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.posts', '"better_supabase"."posts"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.content_entries', '"better_supabase"."content_entries"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.risk_assessments', '"better_supabase"."risk_assessments"', 'assessed_by', true, '{}'::text[], true),
    ('user', 'better_supabase.shift_assignments', '"better_supabase"."shift_assignments"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.shift_swaps', '"better_supabase"."shift_swaps"', 'from_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.shift_availability', '"better_supabase"."shift_availability"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.acknowledgements', '"better_supabase"."acknowledgements"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.acknowledgement_notices', '"better_supabase"."acknowledgement_notices"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.observations', '"better_supabase"."observations"', 'performer_id', true, '{}'::text[], true),
    ('user', 'better_supabase.care_plan_evaluations', '"better_supabase"."care_plan_evaluations"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.inspection_members', '"better_supabase"."inspection_members"', 'user_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.drive_node_texts', '"better_supabase"."drive_node_texts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.guests', '"better_supabase"."guests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.guest_grants', '"better_supabase"."guest_grants"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.comment_tasks', '"better_supabase"."comment_tasks"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.attachments', '"better_supabase"."attachments"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.attachment_versions', '"better_supabase"."attachment_versions"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.retention_policies', '"better_supabase"."retention_policies"', 'organization_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.sso_domains', '"better_supabase"."sso_domains"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sso_providers', '"better_supabase"."sso_providers"', 'organization_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.inbox_conversations', '"better_supabase"."inbox_conversations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_conversation_events', '"better_supabase"."inbox_conversation_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_message_details', '"better_supabase"."inbox_message_details"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_message_deliveries', '"better_supabase"."inbox_message_deliveries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_inbound_events', '"better_supabase"."inbox_inbound_events"', 'tenant_id', true, array['headers']::text[], true),
    ('organization', 'better_supabase.inbox_message_templates', '"better_supabase"."inbox_message_templates"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.memory_message_embeddings', '"better_supabase"."memory_message_embeddings"', 'organization_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.catalog_price_lists', '"better_supabase"."catalog_price_lists"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_prices', '"better_supabase"."product_prices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.catalog_categories', '"better_supabase"."catalog_categories"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_categories', '"better_supabase"."product_categories"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_collections', '"better_supabase"."product_collections"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.collection_products', '"better_supabase"."collection_products"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.catalog_storefronts', '"better_supabase"."catalog_storefronts"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.order_shipping_rates', '"better_supabase"."order_shipping_rates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.orders', '"better_supabase"."orders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_lines', '"better_supabase"."order_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_payments', '"better_supabase"."order_payments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_fulfillments', '"better_supabase"."order_fulfillments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_fulfillment_lines', '"better_supabase"."order_fulfillment_lines"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.case_kinds', '"better_supabase"."case_kinds"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.cases', '"better_supabase"."cases"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.case_actions', '"better_supabase"."case_actions"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.person_identities', '"better_supabase"."person_identities"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.activities', '"better_supabase"."activities"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.goals', '"better_supabase"."goals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employees', '"better_supabase"."employees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employee_private_details', '"better_supabase"."employee_private_details"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employee_contracts', '"better_supabase"."employee_contracts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_items', '"better_supabase"."moderation_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_reports', '"better_supabase"."moderation_reports"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_actions', '"better_supabase"."moderation_actions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_bans', '"better_supabase"."moderation_bans"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.automations', '"better_supabase"."automations"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.automation_versions', '"better_supabase"."automation_versions"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.automation_evaluations', '"better_supabase"."automation_evaluations"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.asset_locations', '"better_supabase"."asset_locations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.assets', '"better_supabase"."assets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.asset_assignments', '"better_supabase"."asset_assignments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.asset_depreciations', '"better_supabase"."asset_depreciations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.score_models', '"better_supabase"."score_models"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.score_model_versions', '"better_supabase"."score_model_versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.scores', '"better_supabase"."scores"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.passes', '"better_supabase"."passes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pass_check_ins', '"better_supabase"."pass_check_ins"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.time_rates', '"better_supabase"."time_rates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.time_invoice_entries', '"better_supabase"."time_invoice_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.leases', '"better_supabase"."leases"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.compliance_policies', '"better_supabase"."compliance_policies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_status_components', '"better_supabase"."incident_status_components"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_status_component_history', '"better_supabase"."incident_status_component_history"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incidents', '"better_supabase"."incidents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_updates', '"better_supabase"."incident_updates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_impacts', '"better_supabase"."incident_impacts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_postmortems', '"better_supabase"."incident_postmortems"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_postmortem_actions', '"better_supabase"."incident_postmortem_actions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_status_pages', '"better_supabase"."incident_status_pages"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.timeline_entries', '"better_supabase"."timeline_entries"', 'organization_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.lead_score_checks', '"better_supabase"."lead_score_checks"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.post_boards', '"better_supabase"."post_boards"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.posts', '"better_supabase"."posts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.content_entries', '"better_supabase"."content_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.qualification_types', '"better_supabase"."qualification_types"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.qualification_requirements', '"better_supabase"."qualification_requirements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.qualifications', '"better_supabase"."qualifications"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.risk_matrices', '"better_supabase"."risk_matrices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.risks', '"better_supabase"."risks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.risk_assessments', '"better_supabase"."risk_assessments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shift_templates', '"better_supabase"."shift_templates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shifts', '"better_supabase"."shifts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shift_assignments', '"better_supabase"."shift_assignments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shift_swaps', '"better_supabase"."shift_swaps"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shift_availability', '"better_supabase"."shift_availability"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_settings', '"better_supabase"."accounting_settings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_accounts', '"better_supabase"."accounting_accounts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_account_roles', '"better_supabase"."accounting_account_roles"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_journals', '"better_supabase"."accounting_journals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_periods', '"better_supabase"."accounting_periods"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_entries', '"better_supabase"."accounting_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_entry_lines', '"better_supabase"."accounting_entry_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_dimensions', '"better_supabase"."accounting_dimensions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_dimension_values', '"better_supabase"."accounting_dimension_values"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_fx_rates', '"better_supabase"."accounting_fx_rates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_tax_codes', '"better_supabase"."accounting_tax_codes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_budgets', '"better_supabase"."accounting_budgets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_budget_lines', '"better_supabase"."accounting_budget_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.acknowledgement_assignments', '"better_supabase"."acknowledgement_assignments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.acknowledgements', '"better_supabase"."acknowledgements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.acknowledgement_notices', '"better_supabase"."acknowledgement_notices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.consent_purposes', '"better_supabase"."consent_purposes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.consents', '"better_supabase"."consents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.observation_definitions', '"better_supabase"."observation_definitions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.observations', '"better_supabase"."observations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.medications', '"better_supabase"."medications"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.medication_orders', '"better_supabase"."medication_orders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.medication_administrations', '"better_supabase"."medication_administrations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.care_plans', '"better_supabase"."care_plans"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.care_plan_problems', '"better_supabase"."care_plan_problems"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.care_plan_goals', '"better_supabase"."care_plan_goals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.care_plan_actions', '"better_supabase"."care_plan_actions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.care_plan_evaluations', '"better_supabase"."care_plan_evaluations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inspection_programs', '"better_supabase"."inspection_programs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inspections', '"better_supabase"."inspections"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inspection_members', '"better_supabase"."inspection_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inspection_findings', '"better_supabase"."inspection_findings"', 'tenant_id', true, '{}'::text[], true)
  ) as t(subject, name, tbl, col, purge, omit, exported)
  ) as t(subject, name, tbl, col, purge, omit, exported)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.find_person_by_identity (
  tenant  uuid,
  channel text,
  address text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select to_jsonb(p) from "better_supabase"."person_identities" i
  join "better_supabase"."people" p on p."id" = i."person_id"
  where i."tenant_id" = find_person_by_identity.tenant
    and i."channel" = trim(find_person_by_identity.channel)
    and i."address" = trim(find_person_by_identity.address)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.inbox_contact_ids()
  RETURNS SETOF uuid
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  return query select p."id" from "better_supabase"."people" p where p."user_id" = (select auth.uid());
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.inbox_contact_json (
  conversation uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not "better_supabase"."inbox_conversation_allowed"(conversation::text) then
    return null;
  end if;
  return (
    select jsonb_build_object('id', p."id", 'name', p."name", 'email', p."email", 'phone', p."phone", 'avatar_url', p."avatar_url", 'user_id', p."user_id")
    from "better_supabase"."inbox_conversations" v
    join "better_supabase"."people" p on p."id" = v."contact_id"
    where v."id" = inbox_contact_json.conversation
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.inbox_contact_read_at (
  conversation uuid
)
  RETURNS timestamp WITH time zone
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  return (
    select k."last_read_at"
    from "better_supabase"."inbox_conversations" v
    join "better_supabase"."people" p on p."id" = v."contact_id"
    join "better_supabase"."conversation_members" k on k."conversation_id" = v."id" and k."user_id" = p."user_id"
    where v."id" = inbox_contact_read_at.conversation
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v."tenant_id", 'inbox.read'), false))
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.inbox_conversation_allowed (
  conversation text,
  write        boolean DEFAULT false
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  return coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce((
    select (case when write then coalesce(better_supabase.can('tenant', v."tenant_id", 'inbox.reply'), false) else coalesce(better_supabase.can('tenant', v."tenant_id", 'inbox.read'), false) end)
      or exists (select 1 from "better_supabase"."people" p where p."id" = v."contact_id" and p."user_id" = (select auth.uid()))
    from "better_supabase"."inbox_conversations" v
    where v."id"::text = inbox_conversation_allowed.conversation
  ), false);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.inbox_conversation_json (
  conversation uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
begin
  return (
    select to_jsonb(v) || jsonb_build_object(
      'contact', "better_supabase"."inbox_contact_json"(v."id"),
      'inbox', (select jsonb_build_object('id', i."id", 'name', i."name", 'channel', i."channel") from "better_supabase"."inboxes" i where i."id" = v."inbox_id"),
      'last_read_at', (select k."last_read_at" from "better_supabase"."conversation_members" k where k."conversation_id" = v."id" and k."user_id" = (select auth.uid())),
      'contact_read_at', "better_supabase"."inbox_contact_read_at"(v."id")
    )
    from "better_supabase"."inbox_conversations" v
    where v."id" = inbox_conversation_json.conversation
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_inbox_conversations (
  tenant uuid  DEFAULT NULL::uuid,
  filter jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
begin
  return (
    select coalesce(jsonb_agg("better_supabase"."inbox_conversation_json"(page."id") || jsonb_build_object('unread', page.unread) order by page."last_message_at" desc, page."id" desc), '[]'::jsonb)
    from (
      select v."id", v."last_message_at",
        v."last_message_at" > coalesce((select k."last_read_at" from "better_supabase"."conversation_members" k where k."conversation_id" = v."id" and k."user_id" = (select auth.uid())), '-infinity'::timestamptz) as unread
      from "better_supabase"."inbox_conversations" v
      where (list_inbox_conversations.tenant is null or v."tenant_id" = list_inbox_conversations.tenant)
        and (filter ->> 'inbox_id' is null or v."inbox_id" = (filter ->> 'inbox_id')::uuid)
        and (coalesce(filter ->> 'status', 'open') = 'all' or v."status" = coalesce(filter ->> 'status', 'open'))
        and (case filter ->> 'assignee'
          when 'me' then v."assignee_id" = (select auth.uid())
          when 'unassigned' then v."assignee_id" is null
          else filter ->> 'assignee' is null or v."assignee_id" = (filter ->> 'assignee')::uuid end)
        and (filter ->> 'team_id' is null or v."team_id" = (filter ->> 'team_id')::uuid)
        and (filter ->> 'contact_id' is null or v."contact_id" = (filter ->> 'contact_id')::uuid)
        and (nullif(filter ->> 'search', '') is null
          or v."subject" ilike '%' || (filter ->> 'search') || '%'
          or v."last_message_preview" ilike '%' || (filter ->> 'search') || '%'
          or "better_supabase"."inbox_contact_json"(v."id") ->> 'name' ilike '%' || (filter ->> 'search') || '%'
          or "better_supabase"."inbox_contact_json"(v."id") ->> 'email' ilike '%' || (filter ->> 'search') || '%')
        and (filter -> 'before' is null
          or (v."last_message_at", v."id") < ((filter -> 'before' ->> 'last_message_at')::timestamptz, (filter -> 'before' ->> 'id')::uuid))
      order by v."last_message_at" desc, v."id" desc
      limit least(greatest(coalesce((filter ->> 'limit')::integer, 50), 1), 200)
    ) page
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_person_identities (
  person uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', i."id", 'tenant_id', i."tenant_id", 'person_id', i."person_id", 'channel', i."channel", 'address', i."address", 'verified_at', i."verified_at", 'created_at', i."created_at") order by i."channel", i."address"), '[]'::jsonb)
  from "better_supabase"."person_identities" i where i."person_id" = list_person_identities.person
$function$;

CREATE OR REPLACE FUNCTION better_supabase.mark_conversation_read (
  conversation uuid
)
  RETURNS timestamp WITH time zone
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_at timestamptz := clock_timestamp();
  v_conv "better_supabase"."inbox_conversations"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if (select auth.uid()) is null or not "better_supabase"."inbox_conversation_allowed"(conversation::text) then
    raise exception 'not allowed to read this conversation' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  select * into v_conv from "better_supabase"."inbox_conversations" v where v."id" = mark_conversation_read.conversation;
  insert into "better_supabase"."conversation_members" as k ("conversation_id", "tenant_id", "user_id", "last_read_at")
  values (v_conv."id", v_conv."tenant_id", (select auth.uid()), v_at)
  on conflict ("conversation_id", "user_id") do update set "last_read_at" = greatest(coalesce(k."last_read_at", excluded."last_read_at"), excluded."last_read_at");
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null and exists (select 1 from "better_supabase"."people" p where p."id" = v_conv."contact_id" and p."user_id" = (select auth.uid())) then
    perform realtime.send(jsonb_build_object('conversation_id', v_conv."id"), 'read', 'messages:' || v_conv."id"::text, true);
  end if;
  return v_at;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.merge_people (
  keep uuid,
  drop uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_keep "better_supabase"."people";
  v_drop "better_supabase"."people";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_keep from "better_supabase"."people" x where x."id" = merge_people.keep for update;
  select * into v_drop from "better_supabase"."people" x where x."id" = merge_people.drop for update;
  if v_keep."id" is null or v_drop."id" is null then
    raise exception 'person not found' using errcode = 'P0002', hint = 'PARTY_NOT_FOUND';
  end if;
  if v_keep."tenant_id" <> v_drop."tenant_id" or v_keep."id" = v_drop."id" or v_drop."merged_into" is not null then
    raise exception 'merge two different, unmerged records of one organization' using errcode = '22023', hint = 'PARTY_MERGE_INVALID';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_keep."tenant_id", 'contacts.manage'), false)) then
    raise exception 'not allowed to change companies and people' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  update "better_supabase"."people" x set "email" = null, "merged_into" = merge_people.keep,
    "archived_at" = coalesce(x."archived_at", now()), "updated_at" = now()
  where x."id" = merge_people.drop;
  update "better_supabase"."people" x set "email" = coalesce(x."email", v_drop."email"), "phone" = coalesce(x."phone", v_drop."phone"), "title" = coalesce(x."title", v_drop."title"), "owner_user_id" = coalesce(x."owner_user_id", v_drop."owner_user_id"), "user_id" = coalesce(x."user_id", v_drop."user_id"), "updated_at" = now()
  where x."id" = merge_people.keep;
  insert into "better_supabase"."company_people" ("tenant_id", "company_id", "person_id", "role", "is_primary")
  select l."tenant_id", l."company_id", merge_people.keep, l."role", false
  from "better_supabase"."company_people" l where l."person_id" = merge_people.drop
  on conflict do nothing;
  delete from "better_supabase"."company_people" l where l."person_id" = merge_people.drop;
  update "better_supabase"."person_identities" i set "person_id" = merge_people.keep where i."person_id" = merge_people.drop;
  update "better_supabase"."inbox_conversations" x set "contact_id" = merge_people.keep where x."contact_id" = merge_people.drop;
  perform better_supabase.merge_subject_refs('better_supabase.people', merge_people.keep::text, merge_people.drop::text);
  perform "better_supabase".emit_event('person.merged', jsonb_build_object('organizationId', v_keep."tenant_id", 'personId', merge_people.keep, 'name', v_keep."name", 'mergedId', merge_people.drop), 'persons/' || merge_people.keep::text, (v_keep."tenant_id"::text)::text, null, 'better-supabase/contacts');
  perform better_supabase.audit_event(
    event_type => 'person.merged',
    category => 'data',
    target_type => 'person',
    record_id => merge_people.keep::text,
    target_label => v_keep."name",
    summary => 'merged ' || v_drop."name" || ' into ' || v_keep."name",
    tenant => (v_keep."tenant_id"::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_keep."tenant_id", 'personId', merge_people.keep, 'name', v_keep."name", 'mergedId', merge_people.drop)
  );
  return (select to_jsonb(x) from "better_supabase"."people" x where x."id" = merge_people.keep);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_contact (
  contact uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_ids uuid[];
  v_messages integer;
  v_paths jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select p."tenant_id" into v_tenant from "better_supabase"."people" p where p."id" = purge_contact.contact;
  if not found then
    raise exception 'contact not found' using errcode = 'P0002', hint = 'CONTACT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'inbox.manage'), false)) then
    raise exception 'not allowed to erase contacts' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  v_ids := array(select v."id" from "better_supabase"."inbox_conversations" v where v."contact_id" = purge_contact.contact);
  select count(*)::integer into v_messages from "better_supabase"."messages" m where m."conversation_id" = any (v_ids);
  with gone as (
    delete from "better_supabase"."attachments" x
    where (x."subject_type" = 'conversation' and x."subject_id" = any (array(select i::text from unnest(v_ids) i)))
      or (x."subject_type" = 'message' and x."subject_id" in (
        select m."id"::text from "better_supabase"."messages" m where m."conversation_id" = any (v_ids)))
    returning x."bucket" as bucket, x."object_path" as path, x."uploaded_at" as uploaded_at
  )
  select coalesce(jsonb_agg(jsonb_build_object('bucket', g.bucket, 'path', g.path)) filter (where g.uploaded_at is not null), '[]'::jsonb)
  into v_paths from gone g;
  delete from "better_supabase"."conversations" k where k."id" = any (v_ids);
  delete from "better_supabase"."person_identities" i where i."person_id" = purge_contact.contact;
  update "better_supabase"."people" p set "merged_into" = null where p."merged_into" = purge_contact.contact;
  delete from "better_supabase"."people" p where p."id" = purge_contact.contact;
  return jsonb_build_object('conversations', cardinality(v_ids), 'messages', v_messages, 'attachments', v_paths);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_inbound (
  input jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_inbox "better_supabase"."inboxes"%rowtype;
  v_contact uuid;
  v_contact_user uuid;
  v_conv "better_supabase"."inbox_conversations"%rowtype;
  v_id uuid;
  v_message uuid;
  v_created boolean := false;
  v_duplicate boolean := false;
  v_input jsonb := coalesce(input -> 'message', '{}'::jsonb);
  v_contact_input jsonb := coalesce(input -> 'contact', '{}'::jsonb);
begin
  select * into v_inbox from "better_supabase"."inboxes" where "id" = (input ->> 'inbox_id')::uuid;
  if not found then
    raise exception 'inbox not found' using errcode = 'P0002', hint = 'INBOX_NOT_FOUND';
  end if;
  if v_contact_input ? 'external_id' and not v_contact_input ? 'identity' then
    v_contact_input := v_contact_input || jsonb_build_object('identity', jsonb_build_object('channel', coalesce(v_contact_input ->> 'channel', v_inbox."channel"), 'external_id', v_contact_input ->> 'external_id'));
  end if;
  select * into v_conv from "better_supabase"."inbox_conversations"
  where "inbox_id" = v_inbox."id" and "thread_id" = input ->> 'thread_id'
  for update;
  if not found then
    v_contact := "better_supabase"."resolve_person"(v_inbox."tenant_id", v_contact_input);
  select p."user_id" into v_contact_user from "better_supabase"."people" p where p."id" = v_contact;
    v_id := gen_random_uuid();
  insert into "better_supabase"."conversations" ("id", "tenant_id", "kind", "access", "created_by")
  values (v_id, v_inbox."tenant_id", 'inbox', 'tenant', (select auth.uid()));
    insert into "better_supabase"."inbox_conversations" ("id", "tenant_id", "inbox_id", "contact_id", "subject", "bot_mode", "thread_id", "metadata")
    values (v_id, v_inbox."tenant_id", v_inbox."id", v_contact, input ->> 'subject', v_inbox."bot_mode", input ->> 'thread_id', coalesce(input -> 'metadata', '{}'::jsonb))
    returning * into v_conv;
    if v_contact_user is not null then
      insert into "better_supabase"."conversation_members" ("conversation_id", "tenant_id", "user_id")
    values (v_id, v_inbox."tenant_id", v_contact_user)
    on conflict do nothing;
    end if;
    v_created := true;
    insert into "better_supabase"."inbox_conversation_events" ("tenant_id", "conversation_id", "type", "actor_id", "data")
  values (v_conv."tenant_id", v_conv."id", 'opened', (select auth.uid()), jsonb_build_object('by', 'channel'));
    perform "better_supabase".emit_event('inbox_conversation.opened', jsonb_build_object('conversationId', v_conv."id", 'organizationId', v_conv."tenant_id"::text, 'inboxId', v_conv."inbox_id", 'contactId', v_conv."contact_id", 'assigneeId', v_conv."assignee_id", 'status', v_conv."status"), 'conversations/' || v_conv."id"::text, (v_conv."tenant_id")::text, null, 'better-supabase/inbox');
  end if;
  if v_input ? 'external_id' then
    v_duplicate := exists (select 1 from "better_supabase"."inbox_message_details" d where d."conversation_id" = v_conv."id" and d."external_id" = v_input ->> 'external_id');
  end if;
  v_message := "better_supabase"."inbox_add_message"(
    v_conv."id",
    v_input - 'kind' - 'attachments',
    case when coalesce(input ->> 'direction', 'inbound') = 'inbound' then 'contact' else coalesce(input ->> 'author_type', 'bot') end,
    null,
    coalesce(input ->> 'direction', 'inbound')
  );
  return jsonb_build_object(
    'conversation_id', v_conv."id",
    'message_id', v_message,
    'contact_id', v_conv."contact_id",
    'tenant_id', v_conv."tenant_id",
    'created', v_created,
    'duplicate', v_duplicate
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.remove_person_identity (
  identity uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select i."tenant_id" into v_tenant from "better_supabase"."person_identities" i where i."id" = remove_person_identity.identity;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'contacts.write'), false)) then
    raise exception 'not allowed to change companies and people' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  delete from "better_supabase"."person_identities" i where i."id" = remove_person_identity.identity;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.resolve_person (
  tenant uuid,
  input  jsonb
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_person uuid;
  v_identity jsonb := input -> 'identity';
  v_channel text := nullif(trim(v_identity ->> 'channel'), '');
  v_address text := nullif(trim(coalesce(v_identity ->> 'address', v_identity ->> 'external_id')), '');
  v_email text := lower(nullif(trim(input ->> 'email'), ''));
  v_name text;
begin
  if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+$' then
    v_email := null;
  end if;
  if nullif(trim(input ->> 'id'), '') is not null then
    select p."id" into v_person from "better_supabase"."people" p
    where p."id" = nullif(trim(input ->> 'id'), '')::uuid and p."tenant_id" = resolve_person.tenant;
    if v_person is null then
      raise exception 'contact not found' using errcode = 'P0002', hint = 'CONTACT_NOT_FOUND';
    end if;
  end if;
  if v_person is null and v_channel is not null and v_address is not null then
    select i."person_id" into v_person from "better_supabase"."person_identities" i
    where i."tenant_id" = resolve_person.tenant and i."channel" = v_channel and i."address" = v_address;
  end if;
  if v_person is null and nullif(trim(input ->> 'user_id'), '') is not null then
    select p."id" into v_person from "better_supabase"."people" p
    where p."tenant_id" = resolve_person.tenant and p."user_id" = nullif(trim(input ->> 'user_id'), '')::uuid
    order by p."archived_at" nulls first, p."created_at", p."id" limit 1;
  end if;
  if v_person is null and v_email is not null then
    select p."id" into v_person from "better_supabase"."people" p
    where p."tenant_id" = resolve_person.tenant and p."email" = v_email and p."archived_at" is null;
  end if;
  if v_person is not null then
    select coalesce(p."merged_into", p."id") into v_person from "better_supabase"."people" p where p."id" = v_person;
    update "better_supabase"."people" p set
      "email" = coalesce(p."email", case when not exists (select 1 from "better_supabase"."people" o where o."tenant_id" = p."tenant_id" and o."email" = v_email and o."archived_at" is null and o."id" <> p."id") then v_email end),
      "phone" = coalesce(p."phone", nullif(trim(input ->> 'phone'), '')),
      "user_id" = coalesce(p."user_id", nullif(trim(input ->> 'user_id'), '')::uuid),
      "avatar_url" = coalesce(nullif(trim(input ->> 'avatar_url'), ''), p."avatar_url"),
      "metadata" = p."metadata" || case when jsonb_typeof(input -> 'metadata') = 'object' then input -> 'metadata' else '{}'::jsonb end,
      "updated_at" = now()
    where p."id" = v_person
      and (p."email", p."phone", p."user_id", p."avatar_url", p."metadata") is distinct from (coalesce(p."email", case when not exists (select 1 from "better_supabase"."people" o where o."tenant_id" = p."tenant_id" and o."email" = v_email and o."archived_at" is null and o."id" <> p."id") then v_email end), coalesce(p."phone", nullif(trim(input ->> 'phone'), '')), coalesce(p."user_id", nullif(trim(input ->> 'user_id'), '')::uuid), coalesce(nullif(trim(input ->> 'avatar_url'), ''), p."avatar_url"), p."metadata" || case when jsonb_typeof(input -> 'metadata') = 'object' then input -> 'metadata' else '{}'::jsonb end);
  else
    v_name := left(coalesce(nullif(trim(input ->> 'name'), ''), v_email, nullif(trim(input ->> 'phone'), ''), v_address, 'Unknown contact'), 300);
    begin
      insert into "better_supabase"."people" ("tenant_id", "name", "email", "phone", "lifecycle", "user_id", "avatar_url", "metadata", "created_by")
      values (resolve_person.tenant, v_name, v_email, nullif(trim(input ->> 'phone'), ''), ('{lead,mql,sql,opportunity,customer}'::text[])[1], nullif(trim(input ->> 'user_id'), '')::uuid, nullif(trim(input ->> 'avatar_url'), ''), case when jsonb_typeof(input -> 'metadata') = 'object' then input -> 'metadata' else '{}'::jsonb end || case when v_email is null and nullif(trim(input ->> 'email'), '') is not null then jsonb_build_object('email', nullif(trim(input ->> 'email'), '')) else '{}'::jsonb end, auth.uid())
      returning "id" into v_person;
      perform "better_supabase".emit_event('person.created', jsonb_build_object('organizationId', resolve_person.tenant, 'personId', v_person, 'name', v_name), 'persons/' || v_person::text, (resolve_person.tenant::text)::text, null, 'better-supabase/contacts');
    exception when unique_violation then
      select p."id" into v_person from "better_supabase"."people" p
      where p."tenant_id" = resolve_person.tenant and p."email" = v_email and p."archived_at" is null;
      if v_person is null then
        raise;
      end if;
    end;
  end if;
  if v_channel is not null and v_address is not null then
    insert into "better_supabase"."person_identities" ("tenant_id", "person_id", "channel", "address")
    values (resolve_person.tenant, v_person, v_channel, v_address)
    on conflict do nothing;
  end if;
  return v_person;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.send_inbox_message (
  conversation uuid,
  input        jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_conv "better_supabase"."inbox_conversations"%rowtype;
  v_id uuid;
  v_author_type text;
  v_direction text;
  v_kind text := coalesce(input ->> 'kind', 'message');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_conv from "better_supabase"."inbox_conversations" where "id" = send_inbox_message.conversation for update;
  if not found then
    raise exception 'conversation not found' using errcode = 'P0002', hint = 'CONVERSATION_NOT_FOUND';
  end if;
  if coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    v_author_type := coalesce(input ->> 'author_type', 'bot');
    v_direction := case when v_author_type = 'contact' then 'inbound' else 'outbound' end;
  elsif exists (select 1 from "better_supabase"."people" p where p."id" = v_conv."contact_id" and p."user_id" = (select auth.uid())) then
    -- The conversation's own contact writes as the contact, staff included.
    if v_kind <> 'message' then
      raise exception 'contacts cannot write notes' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
    end if;
    if input ? 'files' then
      raise exception 'contacts attach their own uploads' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
    end if;
    v_author_type := 'contact';
    v_direction := 'inbound';
  elsif coalesce(better_supabase.can('tenant', v_conv."tenant_id", 'inbox.reply'), false) then
    v_author_type := 'agent';
    v_direction := 'outbound';
  else
    raise exception 'not allowed to write in this conversation' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  v_id := "better_supabase"."inbox_add_message"(v_conv."id", coalesce(input, '{}'::jsonb) - 'author_type', v_author_type, (select auth.uid()), v_direction);
  if v_author_type = 'agent' and v_kind = 'message' and v_conv."bot_mode" = 'bot' then
    update "better_supabase"."inbox_conversations" set "bot_mode" = 'human' where "id" = v_conv."id" returning * into v_conv;
    insert into "better_supabase"."inbox_conversation_events" ("tenant_id", "conversation_id", "type", "actor_id", "data")
  values (v_conv."tenant_id", v_conv."id", 'handoff', (select auth.uid()), jsonb_build_object('from', 'bot', 'to', 'human', 'reason', 'agent_reply'));
  end if;
  return "better_supabase"."inbox_messages_json"(array[v_id]) -> 0;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.start_conversation (
  inbox uuid,
  input jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_inbox "better_supabase"."inboxes"%rowtype;
  v_contact uuid;
  v_contact_user uuid;
  v_conv "better_supabase"."inbox_conversations"%rowtype;
  v_id uuid;
  v_staff boolean;
  v_contact_input jsonb := coalesce(input -> 'contact', '{}'::jsonb);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_inbox from "better_supabase"."inboxes" where "id" = start_conversation.inbox and "archived_at" is null;
  if not found then
    raise exception 'inbox not found' using errcode = 'P0002', hint = 'INBOX_NOT_FOUND';
  end if;
  -- A signed-in caller who names no contact on a widget inbox is the
  -- visitor, staff included, so they can try their own widget.
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and (select auth.uid()) is not null and not (input ? 'contact')
    and v_inbox."channel" = 'in_app' and coalesce((v_inbox."settings" ->> 'widget')::boolean, false) then
    v_staff := false;
    v_contact_input := jsonb_build_object(
      'user_id', (select auth.uid()),
      'name', v_contact_input ->> 'name',
      'email', coalesce((select auth.jwt()) ->> 'email', v_contact_input ->> 'email')
    );
  elsif coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_inbox."tenant_id", 'inbox.reply'), false) then
    v_staff := true;
    if jsonb_typeof(input -> 'contact') = 'string' then
      v_contact_input := jsonb_build_object('id', input ->> 'contact');
    end if;
    if v_contact_input = '{}'::jsonb then
      raise exception 'input.contact is required' using errcode = '22023', hint = 'CONTACT_REQUIRED';
    end if;
  else
    raise exception 'not allowed to open a conversation in this inbox' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  v_contact := "better_supabase"."resolve_person"(v_inbox."tenant_id", v_contact_input);
  select p."user_id" into v_contact_user from "better_supabase"."people" p where p."id" = v_contact;
  v_id := gen_random_uuid();
  insert into "better_supabase"."conversations" ("id", "tenant_id", "kind", "access", "created_by")
  values (v_id, v_inbox."tenant_id", 'inbox', 'tenant', (select auth.uid()));
  insert into "better_supabase"."inbox_conversations" ("id", "tenant_id", "inbox_id", "contact_id", "subject", "priority", "bot_mode", "thread_id", "assignee_id", "metadata")
  values (
    v_id, v_inbox."tenant_id", v_inbox."id", v_contact, input ->> 'subject', coalesce(input ->> 'priority', 'normal'),
    coalesce(input ->> 'bot_mode', v_inbox."bot_mode"), coalesce(input ->> 'thread_id', 'inbox:' || v_inbox."id"::text || ':' || v_id::text),
    case when v_staff then (input ->> 'assignee_id')::uuid end, coalesce(input -> 'metadata', '{}'::jsonb)
  )
  returning * into v_conv;
  if v_contact_user is not null then
    insert into "better_supabase"."conversation_members" ("conversation_id", "tenant_id", "user_id")
    values (v_id, v_inbox."tenant_id", v_contact_user)
    on conflict do nothing;
  end if;
  if v_conv."assignee_id" is not null then
    insert into "better_supabase"."conversation_members" ("conversation_id", "tenant_id", "user_id")
    values (v_id, v_inbox."tenant_id", v_conv."assignee_id")
    on conflict do nothing;
  end if;
  insert into "better_supabase"."inbox_conversation_events" ("tenant_id", "conversation_id", "type", "actor_id", "data")
  values (v_conv."tenant_id", v_conv."id", 'opened', (select auth.uid()), '{}'::jsonb);
  perform "better_supabase".emit_event('inbox_conversation.opened', jsonb_build_object('conversationId', v_conv."id", 'organizationId', v_conv."tenant_id"::text, 'inboxId', v_conv."inbox_id", 'contactId', v_conv."contact_id", 'assigneeId', v_conv."assignee_id", 'status', v_conv."status"), 'conversations/' || v_conv."id"::text, (v_conv."tenant_id")::text, null, 'better-supabase/inbox');
  if input ? 'message' then
    perform "better_supabase"."inbox_add_message"(
      v_conv."id",
      case when jsonb_typeof(input -> 'message') = 'string' then jsonb_build_object('body', input ->> 'message') else input -> 'message' end,
      case when v_staff then (case when (select auth.uid()) is null then 'bot' else 'agent' end) else 'contact' end,
      (select auth.uid()),
      case when v_staff then 'outbound' else 'inbound' end
    );
  end if;
  return "better_supabase"."inbox_conversation_json"(v_conv."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.upsert_contact (
  tenant uuid,
  input  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_person uuid;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', upsert_contact.tenant, 'inbox.reply'), false)) then
    raise exception 'not allowed to edit contacts' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  v_person := "better_supabase"."resolve_person"(upsert_contact.tenant, coalesce(input, '{}'::jsonb));
  return (
    select jsonb_build_object('id', p."id", 'tenant_id', p."tenant_id", 'user_id', p."user_id", 'name', p."name", 'email', p."email", 'phone', p."phone", 'avatar_url', p."avatar_url", 'metadata', p."metadata", 'created_at', p."created_at")
    from "better_supabase"."people" p where p."id" = v_person
  );
end;
$function$;

ALTER TABLE "better_supabase"."inbox_conversations"
  ADD CONSTRAINT "inbox_conversations_contact_id_fkey" FOREIGN KEY (contact_id) REFERENCES better_supabase.people(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."people"
  ADD CONSTRAINT "people_metadata_check" CHECK ((jsonb_typeof(metadata) = 'object'::text));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."conversations"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR
CASE
    WHEN (kind = 'inbox'::text) THEN better_supabase.inbox_conversation_allowed((id)::text)
    ELSE
      ((((tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.read'::text) AS tenant_ids_with)) OR ((access = 'subject'::text) AND (subject_type = 'drive_node'::text)))
      AND
    CASE access
        WHEN 'tenant'::text THEN true
        WHEN 'members'::text THEN better_supabase.is_conversation_member(id)
        WHEN 'subject'::text THEN COALESCE(better_supabase.can_subject(subject_type, subject_id, 'read'::text), false)
        ELSE false
    END) OR ((kind = 'subject'::text) AND (((tenant_id)::text, subject_type, subject_id) IN ( SELECT g.tenant,
        g.subject_type,
        g.subject_id
       FROM better_supabase.portal_subjects('read'::text) g(tenant, subject_type, subject_id)))))
END));

CREATE POLICY "conversations_read" ON "better_supabase"."conversations"
  FOR SELECT
  TO "authenticated"
  USING (
CASE
    WHEN (kind = 'inbox'::text) THEN better_supabase.inbox_conversation_allowed((id)::text)
    ELSE
      ((((tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.read'::text) AS tenant_ids_with)) OR ((access = 'subject'::text) AND (subject_type = 'drive_node'::text)))
      AND
    CASE access
        WHEN 'tenant'::text THEN true
        WHEN 'members'::text THEN better_supabase.is_conversation_member(id)
        WHEN 'subject'::text THEN COALESCE(better_supabase.can_subject(subject_type, subject_id, 'read'::text), false)
        ELSE false
    END) OR ((kind = 'subject'::text) AND (((tenant_id)::text, subject_type, subject_id) IN ( SELECT g.tenant,
        g.subject_type,
        g.subject_id
       FROM better_supabase.portal_subjects('read'::text) g(tenant, subject_type, subject_id)))))
END);

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."inbox_conversations"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('inbox.read'::text)
    AS tenant_ids_with)) OR (contact_id IN ( SELECT better_supabase.inbox_contact_ids() AS inbox_contact_ids)))));

CREATE POLICY "conversations_read" ON "better_supabase"."inbox_conversations"
  FOR SELECT
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.tenant_ids_with('inbox.read'::text) AS tenant_ids_with)) OR (contact_id IN ( SELECT better_supabase.inbox_contact_ids() AS
    inbox_contact_ids))));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."person_identities"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."person_identities"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."person_identities"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contacts.read'::text)
    AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."person_identities"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

REVOKE ALL ON FUNCTION "api"."add_person_identity"(uuid, text, text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."add_person_identity"(uuid, text, text, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."find_person_by_identity"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."find_person_by_identity"(uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_person_identities"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_person_identities"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."remove_person_identity"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."remove_person_identity"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."add_person_identity"(uuid, text, text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."add_person_identity"(uuid, text, text, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."find_person_by_identity"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."find_person_by_identity"(uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."inbox_contact_ids"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."inbox_contact_ids"() TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."inbox_contact_json"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."inbox_contact_json"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."inbox_conversation_allowed"(text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."inbox_conversation_allowed"(text, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_person_identities"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_person_identities"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."remove_person_identity"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."remove_person_identity"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."resolve_person"(uuid, jsonb) FROM PUBLIC;
