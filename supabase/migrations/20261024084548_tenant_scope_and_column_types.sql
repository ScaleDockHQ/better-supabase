SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.as_column_type (
  value  text,
  target anyelement
)
  RETURNS anyelement
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."as_column_type"($1, $2) $function$;

CREATE OR REPLACE FUNCTION better_supabase.as_column_type (
  value  text,
  target anyelement
)
  RETURNS anyelement
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
begin
  return value;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_transition_work_item()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if tg_op = 'INSERT' then
    if new."state" is null then
      new."state" := 'backlog';
    end if;
    
    
    return new;
  end if;
  if new."state" is not distinct from old."state" then
    return new;
  end if;
  if not (case old."state"::text when 'triage' then new."state"::text = any ('{backlog,unstarted,started,completed,canceled}'::text[]) when 'backlog' then new."state"::text = any ('{triage,unstarted,started,completed,canceled}'::text[]) when 'unstarted' then new."state"::text = any ('{triage,backlog,started,completed,canceled}'::text[]) when 'started' then new."state"::text = any ('{triage,backlog,unstarted,completed,canceled}'::text[]) when 'completed' then new."state"::text = any ('{triage,backlog,unstarted,started,canceled}'::text[]) when 'canceled' then new."state"::text = any ('{triage,backlog,unstarted,started,completed}'::text[]) else false end) then
    raise exception 'that status change is not allowed' using errcode = '22023', hint = 'STATE_TRANSITION_INVALID';
  end if;
  insert into "better_supabase"."status_history" ("tenant_id", "subject_type", "subject_id", "from_status", "to_status", "actor_user_id", "reason")
        values (new."tenant_id", 'work_item', new."id"::text, old."state"::text, new."state"::text, auth.uid(), nullif(current_setting('better_supabase.transition_reason', true), ''));
  
  perform "better_supabase".emit_event('status.changed', jsonb_build_object('organizationId', new."tenant_id"::text, 'subjectType', 'work_item', 'subjectId', new."id"::text, 'from', old."state"::text, 'to', new."state"::text, 'reason', nullif(current_setting('better_supabase.transition_reason', true), '')), 'statuses/work_item/' || new."id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/state-machine');
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_form_submissions (
  form_id   uuid,
  status    text                     DEFAULT NULL::text,
  page_size integer                  DEFAULT 50,
  before    timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_all boolean;
  v_rows jsonb;
begin
  select x."tenant_id" into v_tenant from "better_supabase"."forms" x where x."id" = list_form_submissions.form_id;
  if not found then
    raise exception 'form not found' using errcode = 'P0002', hint = 'FORM_NOT_FOUND';
  end if;
  v_all := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'forms.review'), false);
  select coalesce(jsonb_agg(jsonb_build_object('id', r."id", 'organizationId', r."tenant_id", 'formId', r."form_id", 'versionId', r."version_id", 'subjectType', r."subject_type", 'subjectId', r."subject_id", 'respondentId', r."respondent_id", 'answers', r."answers", 'status', r."status", 'source', r."source", 'reviewedBy', r."reviewed_by", 'reviewedAt', r."reviewed_at", 'createdAt', r."created_at", 'submittedAt', r."submitted_at", 'updatedAt', r."updated_at", 'score', r."score", 'maxScore', r."max_score", 'passed', r."passed") order by r."created_at" desc), '[]'::jsonb) into v_rows
  from (
    select * from "better_supabase"."form_submissions" x
    where x."form_id" = list_form_submissions.form_id
      and (v_all or x."respondent_id" = auth.uid())
      and (list_form_submissions.status is null or x."status"::text = list_form_submissions.status)
      and (list_form_submissions.before is null or x."created_at" < list_form_submissions.before)
    order by x."created_at" desc
    limit least(greatest(coalesce(list_form_submissions.page_size, 50), 1), 200)
  ) r;
  return v_rows;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_forms (
  tenant uuid,
  status text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_rows jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_forms.tenant, 'forms.read'), false)) then
    raise exception 'not allowed to read forms' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'title', x."title", 'description', x."description", 'status', x."status", 'currentVersionId', x."current_version_id", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."created_at" desc), '[]'::jsonb) into v_rows
  from "better_supabase"."forms" x
  where x."tenant_id" = list_forms.tenant
    and (list_forms.status is null or x."status"::text = list_forms.status);
  return v_rows;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.transition (
  subject_type text,
  subject_id   text,
  to_status    text,
  reason       text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_found boolean;
begin
  perform set_config('better_supabase.transition_reason', coalesce(transition.reason, ''), true);
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_status_transition"(text, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::text)', v_hook::oid::regproc)
        using transition.subject_type, transition.subject_id, transition.to_status;
    end if;
  end;
  case transition.subject_type
    when 'work_item' then
      update "better_supabase"."work_items" s set "state" = better_supabase.as_column_type(transition.to_status, (null::"better_supabase"."work_items")."state")
      where s."id" = (transition.subject_id)::uuid;
    else
      raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
  end case;
  v_found := found;
  perform set_config('better_supabase.transition_reason', '', true);
  if not v_found then
    raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_status_transition"(text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text)', v_hook::oid::regproc)
        using transition.subject_type, transition.to_status;
    end if;
  end;
  return true;
end;
$function$;

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."access_requests"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('access_requests.read'::text) AS tenant_ids_with)) OR (user_id = ( SELECT auth.uid() AS uid)))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."activity_entries"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((organization_id IN ( SELECT
    better_supabase.tenant_ids_with('activity.read'::text) AS tenant_ids_with)) AND
    ((subject_type IS NULL) OR (subject_id IS NULL) OR (NOT (subject_type = ANY
    ('{message,conversation,channel,company,person,deal,course,post,engagement,quote,work_item,employee,invoice,ledger_account,product,product_variant,order,calendar_event,booking,asset,asset_location,lease,expense_report,expense_line,donation_fund,work_order,shipment,contract,control,policy,incident,content_entry,form,document,customer,drive_node,application,project,task}'::text[]))) OR better_supabase.activity_subject_readable(subject_type, subject_id)))))
  WITH CHECK ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."agent_installs"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (user_id = ( SELECT auth.uid() AS uid))))
  WITH CHECK ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."agents"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((owner_id = ( SELECT auth.uid() AS uid)) OR ((published_at IS
    NOT NULL) AND
    ((visibility = 'public'::text) OR ((visibility = 'organization'::text) AND (organization_id IN ( SELECT better_supabase.tenant_ids_with('ai.read'::text) AS tenant_ids_with)))))
    OR (organization_id IN ( SELECT better_supabase.tenant_ids_with('ai.moderate'::text) AS tenant_ids_with)))))
  WITH CHECK ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."ai_batch_items"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (EXISTS ( SELECT 1
   FROM better_supabase.ai_batches y
  WHERE (y.id = ai_batch_items.batch_id)))))
  WITH CHECK ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."ai_batches"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((user_id = ( SELECT auth.uid() AS uid)) OR (organization_id IN (
    SELECT better_supabase.tenant_ids_with('ai.admin'::text) AS tenant_ids_with)))))
  WITH CHECK ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."ai_chats"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((owner_id = ( SELECT auth.uid() AS uid)) OR ((visibility =
    'organization'::text) AND (organization_id IN ( SELECT better_supabase.tenant_ids_with('ai_chat.read'::text) AS tenant_ids_with))))))
  WITH CHECK ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."ai_documents"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((owner_id = ( SELECT auth.uid() AS uid)) OR (organization_id IN (
    SELECT better_supabase.tenant_ids_with('ai.admin'::text) AS tenant_ids_with)) OR ((chat_id IS NOT NULL) AND better_supabase.ai_chat_can_read(chat_id)))))
  WITH CHECK ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."ai_files"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((owner_id = ( SELECT auth.uid() AS uid)) OR (organization_id IN (
    SELECT better_supabase.tenant_ids_with('ai.admin'::text) AS tenant_ids_with)) OR ((chat_id IS NOT NULL) AND better_supabase.ai_chat_can_read(chat_id)))))
  WITH CHECK ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."ai_message_embeddings"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (user_id = ( SELECT auth.uid() AS uid))))
  WITH CHECK ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."ai_projects"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (owner_id = ( SELECT auth.uid() AS uid))))
  WITH CHECK ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."ai_provider_keys"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (organization_id IN ( SELECT
    better_supabase.tenant_ids_with('ai.admin'::text) AS tenant_ids_with))))
  WITH CHECK ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."ai_sandboxes"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((user_id = ( SELECT auth.uid() AS uid)) OR (organization_id IN (
    SELECT better_supabase.tenant_ids_with('ai_chat.admin'::text) AS tenant_ids_with)))))
  WITH CHECK ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."ai_scheduled_tasks"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((user_id = ( SELECT auth.uid() AS uid)) OR (organization_id IN (
    SELECT better_supabase.tenant_ids_with('ai.admin'::text) AS tenant_ids_with)))))
  WITH CHECK ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."ai_task_runs"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((user_id = ( SELECT auth.uid() AS uid)) OR (organization_id IN (
    SELECT better_supabase.tenant_ids_with('ai.admin'::text) AS tenant_ids_with)))))
  WITH CHECK ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."application_scorecards"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('hiring.read'::text)
    AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."applications"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('hiring.read'::text)
    AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."approval_decisions"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('approvals.read'::text) AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."approval_requests"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (((tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('approvals.read'::text) AS tenant_ids_with)) AND (NOT (subject_type = 'ai_tool_approval'::text))) OR
    (requested_by = ( SELECT auth.uid() AS uid)))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."asset_assignments"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (asset_id IN ( SELECT y.id
   FROM better_supabase.assets y))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."asset_locations"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('assets.read'::text)
    AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."assets"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('assets.read'::text)
    AS tenant_ids_with)) OR ((assignee_type = 'member'::text) AND (assignee_id = (( SELECT auth.uid() AS uid))::text)))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."assignment_queue_members"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('assignment.read'::text) AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."assignment_queues"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('assignment.read'::text) AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."assignments"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('assignment.read'::text) AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."attachment_versions"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (EXISTS ( SELECT 1
   FROM better_supabase.attachments a
  WHERE (a.id = attachment_versions.attachment_id)))))
  WITH CHECK ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."attachments"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (((organization_id IN ( SELECT
    better_supabase.tenant_ids_with('attachments.read'::text) AS tenant_ids_with)) OR (((organization_id)::text, subject_type, subject_id) IN ( SELECT g.tenant,
    g.subject_type,
    g.subject_id
   FROM better_supabase.portal_subjects('read'::text) g(tenant, subject_type, subject_id)))) AND
     better_supabase.attachment_subject_readable(subject_type, subject_id, organization_id)) OR
     ((uploaded_by = ( SELECT auth.uid() AS uid)) OR (organization_id IN ( SELECT better_supabase.tenant_ids_with('attachments.manage'::text) AS tenant_ids_with)))))
  WITH
    CHECK
    (((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((uploaded_by = ( SELECT auth.uid() AS uid)) AND
    (COALESCE(better_supabase.can('tenant'::text, organization_id,
CASE subject_type
    WHEN 'message'::text THEN 'messages.send'::text
    WHEN 'conversation'::text THEN 'messages.send'::text
    WHEN 'expense_line'::text THEN 'expenses.submit'::text
    ELSE 'attachments.upload'::text
END), false) OR (((organization_id)::text, subject_type, subject_id) IN ( SELECT g.tenant,
    g.subject_type,
    g.subject_id
   FROM better_supabase.portal_subjects('upload'::text) g(tenant, subject_type, subject_id)))) AND
     better_supabase.attachment_subject_readable(subject_type, subject_id, organization_id))));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."audit_events"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((organization_id IN ( SELECT better_supabase.audit_read_tenants() AS
    audit_read_tenants)) OR ( SELECT better_supabase.audit_reads_all() AS audit_reads_all))))
  WITH CHECK ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."booking_availability"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('bookings.read'::text) AS tenant_ids_with)) OR
    (tenant_id IN ( SELECT better_supabase.tenant_ids_with('bookings.create'::text) AS tenant_ids_with)))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."booking_exceptions"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('bookings.read'::text)
    AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."booking_resources"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('bookings.read'::text) AS tenant_ids_with)) OR
    (tenant_id IN ( SELECT better_supabase.tenant_ids_with('bookings.create'::text) AS tenant_ids_with)))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."booking_services"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('bookings.read'::text) AS tenant_ids_with)) OR
    (tenant_id IN ( SELECT better_supabase.tenant_ids_with('bookings.create'::text) AS tenant_ids_with)))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."bookings"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('bookings.read'::text) AS tenant_ids_with)) OR (customer_user_id = ( SELECT auth.uid() AS uid)) OR
    (((tenant_id)::text, 'booking'::text, (id)::text) IN ( SELECT g.tenant,
    g.subject_type,
    g.subject_id
   FROM better_supabase.portal_subjects('read'::text) g(tenant, subject_type, subject_id))))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."bulk_runs"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (created_by = ( SELECT auth.uid() AS uid))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."calendar_attendees"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('calendar.read'::text) AS tenant_ids_with)) OR (user_id = ( SELECT auth.uid() AS uid)))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."calendar_events"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('calendar.read'::text)
    AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."calendar_working_hours"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('calendar.read'::text) AS tenant_ids_with)) OR (user_id = ( SELECT auth.uid() AS uid)))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."calendars"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('calendar.read'::text)
    AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."cart_lines"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('orders.read'::text)
    AS tenant_ids_with)) OR (EXISTS ( SELECT 1
   FROM better_supabase.carts x
  WHERE ((x.id = cart_lines.cart_id) AND (x.user_id = ( SELECT auth.uid() AS uid))))))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."cart_promotion_codes"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('promotions.read'::text) AS tenant_ids_with)) OR (EXISTS ( SELECT 1
   FROM better_supabase.carts x
  WHERE ((x.id = cart_promotion_codes.cart_id) AND (x.user_id = ( SELECT auth.uid() AS uid))))))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."carts"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((user_id = ( SELECT auth.uid() AS uid)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('orders.read'::text) AS tenant_ids_with)))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."catalog_channel_products"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text)
    AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."catalog_channels"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text)
    AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."categories"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text)
    AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."channels"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (EXISTS ( SELECT 1
   FROM better_supabase.conversations c
  WHERE (c.id = channels.id)))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."collection_products"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text)
    AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."comment_tasks"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR better_supabase.comment_message_readable(message_id, organization_id)))
  WITH
    CHECK
    (((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((created_by = ( SELECT auth.uid() AS uid)) AND
    better_supabase.comment_message_readable(message_id, organization_id))));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."companies"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('parties.read'::text)
    AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."company_people"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('parties.read'::text)
    AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."connector_grants"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (user_id = ( SELECT auth.uid() AS uid))))
  WITH CHECK ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."connector_servers"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (organization_id IN ( SELECT
    better_supabase.tenant_ids_with('ai.read'::text) AS tenant_ids_with))))
  WITH CHECK ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."contact_identities"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('inbox.read'::text) AS
    tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."contacts"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('inbox.read'::text)
    AS tenant_ids_with)) OR (user_id = ( SELECT auth.uid() AS uid)))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."content_entries"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('content.read'::text)
    AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."contract_obligations"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((owner_id = ( SELECT auth.uid() AS uid)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('contracts.read'::text) AS tenant_ids_with)))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."contracts"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((owner_id = ( SELECT auth.uid() AS uid)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('contracts.read'::text) AS tenant_ids_with)))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."control_evidence"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('controls.read'::text)
    AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."control_frameworks"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('controls.read'::text)
    AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."controls"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('controls.read'::text)
    AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."conversation_events"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('inbox.read'::text) AS
    tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."conversation_members"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((user_id = ( SELECT auth.uid() AS uid)) OR (EXISTS ( SELECT 1
   FROM better_supabase.conversations c
  WHERE (c.id = conversation_members.conversation_id))))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."conversations"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR
CASE
    WHEN (kind = 'inbox'::text) THEN better_supabase.inbox_conversation_allowed((id)::text)
    ELSE (((tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.read'::text) AS tenant_ids_with)) AND
    CASE access
        WHEN 'tenant'::text THEN true
        WHEN 'members'::text THEN better_supabase.is_conversation_member(id)
        WHEN 'subject'::text THEN COALESCE(better_supabase.can_subject(subject_type, subject_id, 'read'::text), false)
        ELSE false
    END) OR ((kind = 'subject'::text) AND (((tenant_id)::text, subject_type, subject_id) IN ( SELECT g.tenant,
        g.subject_type,
        g.subject_id
       FROM better_supabase.portal_subjects('read'::text) g(tenant, subject_type, subject_id)))))
END))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."course_certificates"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((user_id = ( SELECT auth.uid() AS uid)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('courses.enroll'::text) AS tenant_ids_with)) OR
    (tenant_id IN ( SELECT better_supabase.tenant_ids_with('courses.manage'::text) AS tenant_ids_with)))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."course_lesson_progress"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((user_id = ( SELECT auth.uid() AS uid)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('courses.enroll'::text) AS tenant_ids_with)) OR
    (tenant_id IN ( SELECT better_supabase.tenant_ids_with('courses.manage'::text) AS tenant_ids_with)))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."course_lessons"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('courses.manage'::text) AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."course_modules"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (EXISTS ( SELECT 1
   FROM better_supabase.courses x
  WHERE (x.id = course_modules.course_id)))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."courses"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (((status = 'published'::text) AND (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('courses.read'::text) AS tenant_ids_with))) OR
    (tenant_id IN ( SELECT better_supabase.tenant_ids_with('courses.manage'::text) AS tenant_ids_with)))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."custom_emoji"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('reactions.read'::text) AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."deal_contacts"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((EXISTS ( SELECT 1
   FROM better_supabase.deals x
  WHERE (x.id = deal_contacts.deal_id))) AND better_supabase.can_subject(contact_type, contact_id, 'read'::text))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."deal_lines"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (EXISTS ( SELECT 1
   FROM better_supabase.deals x
  WHERE (x.id = deal_lines.parent_id)))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."deal_members"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((user_id = ( SELECT auth.uid() AS uid)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('deals.read'::text) AS tenant_ids_with)))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."deals"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('deals.read'::text) AS
    tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."dispatch_route_stops"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('dispatch.read'::text)
    AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."dispatch_routes"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((technician_id = ( SELECT auth.uid() AS uid)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('dispatch.read'::text) AS tenant_ids_with)))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."documents"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('documents.read'::text) AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."donation_funds"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('donations.read'::text) AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."donation_receipts"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('donations.read'::text) AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."donations"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('donations.read'::text) AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."drive_nodes"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((deleted_at IS NULL) AND better_supabase.drive_can(id, 'viewer'::text))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."employee_contracts"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('employees.view_sensitive'::text) AS tenant_ids_with)) OR (EXISTS ( SELECT 1
   FROM better_supabase.employees x
  WHERE ((x.id = employee_contracts.employee_id) AND (x.user_id = ( SELECT auth.uid() AS uid))))))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."employee_private_details"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('employees.view_sensitive'::text) AS tenant_ids_with)) OR (user_id = ( SELECT auth.uid() AS uid)))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."employees"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('employees.read'::text) AS tenant_ids_with)) OR (user_id = ( SELECT auth.uid() AS uid)))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."engagement_subjects"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('engagements.read'::text) AS tenant_ids_with)) AND better_supabase.can_subject(subject_type, subject_id, 'read'::text))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."engagements"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('engagements.read'::text) AS tenant_ids_with)) AND ((NOT (EXISTS ( SELECT 1
   FROM better_supabase.engagement_subjects x
  WHERE (x.engagement_id = engagements.id)))) OR (EXISTS ( SELECT 1
   FROM better_supabase.engagement_subjects x
  WHERE ((x.engagement_id = engagements.id) AND better_supabase.can_subject(x.subject_type, x.subject_id, 'read'::text))))))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."enrichments"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('enrichment.read'::text) AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."enrollment_programs"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('enrollments.read'::text) AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."enrollment_steps"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (EXISTS ( SELECT 1
   FROM better_supabase.enrollments x
  WHERE (x.id = enrollment_steps.enrollment_id)))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."enrollments"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((user_id = ( SELECT auth.uid() AS uid)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('enrollments.read'::text) AS tenant_ids_with)))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."evidence_tasks"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((assignee_id = ( SELECT auth.uid() AS uid)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('controls.read'::text) AS tenant_ids_with)))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."expense_categories"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('expenses.read'::text)
    AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."expense_lines"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((EXISTS ( SELECT 1
   FROM better_supabase.expense_reports p
  WHERE ((p.id = expense_lines.report_id) AND (p.user_id = ( SELECT auth.uid() AS uid))))) OR
    (tenant_id IN ( SELECT better_supabase.tenant_ids_with('expenses.read'::text) AS tenant_ids_with)))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."expense_reports"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((user_id = ( SELECT auth.uid() AS uid)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('expenses.read'::text) AS tenant_ids_with)))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."field_changes"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('history.read'::text)
    AS tenant_ids_with)) AND COALESCE(better_supabase.can_subject(subject_type, subject_id, 'read'::text), false))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."field_definitions"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."field_values"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."forecast_snapshot_deals"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('forecasts.read'::text) AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."forecast_snapshots"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('forecasts.read'::text) AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."form_submissions"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('forms.review'::text)
    AS tenant_ids_with)) OR (respondent_id = ( SELECT auth.uid() AS uid)))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."form_versions"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('forms.read'::text) AS
    tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."forms"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('forms.read'::text) AS
    tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."fulfillment_lines"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('orders.read'::text)
    AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."fulfillments"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('orders.read'::text)
    AS tenant_ids_with)) OR (EXISTS ( SELECT 1
   FROM better_supabase.orders o
  WHERE ((o.id = fulfillments.order_id) AND (o.customer_id = ( SELECT auth.uid() AS uid))))))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."guest_grants"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('guests.read'::text)
    AS tenant_ids_with)) OR (guest_id IN ( SELECT x.id
   FROM better_supabase.guests x
  WHERE (x.user_id = ( SELECT auth.uid() AS uid)))))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."guests"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('guests.read'::text)
    AS tenant_ids_with)) OR (user_id = ( SELECT auth.uid() AS uid)))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."import_runs"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."inbox_conversations"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('inbox.read'::text)
    AS tenant_ids_with)) OR (contact_id IN ( SELECT better_supabase.inbox_contact_ids() AS inbox_contact_ids)))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."inbox_message_details"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('inbox.read'::text) AS
    tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."inboxes"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('inbox.read'::text) AS
    tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."incident_impacts"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('incidents.read'::text) AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."incident_postmortems"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('incidents.read'::text) AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."incident_updates"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('incidents.read'::text) AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."incidents"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('incidents.read'::text) AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."interviews"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('hiring.read'::text)
    AS tenant_ids_with)) OR (( SELECT auth.uid() AS uid) = ANY (interviewer_user_ids)))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."inventory_locations"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('inventory.read'::text) AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."invitations"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (organization_id IN ( SELECT better_supabase.invitation_tenant_ids() AS
    invitation_tenant_ids))))
  WITH CHECK ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."invoice_lines"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (EXISTS ( SELECT 1
   FROM better_supabase.invoices x
  WHERE (x.id = invoice_lines.parent_id)))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."invoices"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('invoices.read'::text) AS tenant_ids_with)) OR (((tenant_id)::text, 'invoice'::text, (id)::text) IN ( SELECT g.tenant,
    g.subject_type,
    g.subject_id
   FROM better_supabase.portal_subjects('read'::text) g(tenant, subject_type, subject_id))) OR (((tenant_id)::text, company_type, company_id) IN ( SELECT g.tenant,
    g.party_type,
    g.party_id
   FROM better_supabase.portal_parties() g(tenant, party_type, party_id))) OR (((tenant_id)::text, contact_type, contact_id) IN ( SELECT g.tenant,
    g.party_type,
    g.party_id
   FROM better_supabase.portal_parties() g(tenant, party_type, party_id))))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."iterations"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('work_items.read'::text) AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."job_openings"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('hiring.read'::text)
    AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."knowledge_documents"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((owner_id = ( SELECT auth.uid() AS uid)) OR ((scope = ANY
    (ARRAY['organization'::text, 'agent'::text])) AND (organization_id IN ( SELECT better_supabase.tenant_ids_with('ai.read'::text) AS tenant_ids_with))) OR
    (organization_id IN ( SELECT better_supabase.tenant_ids_with('ai.admin'::text) AS tenant_ids_with)) OR ((scope = 'chat'::text) AND ((scope_id IS
    NOT NULL) AND better_supabase.ai_chat_can_read(scope_id))))))
  WITH CHECK ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."lead_score_checks"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('scores.compute'::text) AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."lease_agreements"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('leases.read'::text)
    AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."lease_charges"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('leases.read'::text)
    AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."ledger_accounts"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('ledger.read'::text)
    AS tenant_ids_with)) OR (owner_id = ( SELECT auth.uid() AS uid)) OR ((tenant_id, read_permission) IN ( SELECT g.tenant,
    g.permission
   FROM better_supabase.ledger_read_grants() g(tenant, permission))))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."ledger_balances"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (account_id IN ( SELECT y.id
   FROM better_supabase.ledger_accounts y))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."ledger_entries"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (account_id IN ( SELECT y.id
   FROM better_supabase.ledger_accounts y))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."ledger_holds"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (account_id IN ( SELECT y.id
   FROM better_supabase.ledger_accounts y))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."ledger_transactions"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('ledger.read'::text)
    AS tenant_ids_with)) OR (EXISTS ( SELECT 1
   FROM better_supabase.ledger_entries y
  WHERE (y.transaction_id = y.id))))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."mail_accounts"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((user_id = ( SELECT auth.uid() AS uid)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('mail.manage'::text) AS tenant_ids_with)))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."mail_messages"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR better_supabase.mail_thread_visible(thread_id)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."mail_thread_subjects"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR better_supabase.mail_thread_visible(thread_id)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."mail_threads"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR better_supabase.mail_thread_visible(id)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."mail_tracked_links"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (EXISTS ( SELECT 1
   FROM better_supabase.mail_messages y
  WHERE ((y.id = mail_tracked_links.message_id) AND better_supabase.mail_thread_visible(y.thread_id))))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."mail_tracking_events"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (EXISTS ( SELECT 1
   FROM better_supabase.mail_messages y
  WHERE ((y.id = mail_tracking_events.message_id) AND better_supabase.mail_thread_visible(y.thread_id))))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."maintenance_request_assignees"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('maintenance_requests.read'::text) AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."maintenance_request_checklist_items"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('maintenance_requests.read'::text) AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."maintenance_requests"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('maintenance_requests.read'::text) AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."memories"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((owner_id = ( SELECT auth.uid() AS uid)) OR ((scope =
    'organization'::text) AND (organization_id IN ( SELECT better_supabase.tenant_ids_with('ai.read'::text) AS tenant_ids_with))))))
  WITH CHECK ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."message_deliveries"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('inbox.read'::text) AS
    tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."message_edits"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (EXISTS ( SELECT 1
   FROM better_supabase.messages m
  WHERE (m.id = message_edits.message_id)))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."message_record_mentions"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (EXISTS ( SELECT 1
   FROM better_supabase.messages m
  WHERE (m.id = message_record_mentions.message_id)))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."message_templates"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('inbox.read'::text) AS
    tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."messages"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (((sent_at IS
    NOT NULL) OR (author_id = ( SELECT auth.uid() AS uid))) AND (EXISTS ( SELECT 1
   FROM better_supabase.conversations c
  WHERE (c.id = messages.conversation_id))) AND ((kind = 'message'::text) OR better_supabase.inbox_note_readable(conversation_id)))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."moderation_actions"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('moderation.read'::text) AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."moderation_bans"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((user_id = ( SELECT auth.uid() AS uid)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('moderation.read'::text) AS tenant_ids_with)))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."moderation_items"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('moderation.read'::text) AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."moderation_reports"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((reporter_id = ( SELECT auth.uid() AS uid)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('moderation.read'::text) AS tenant_ids_with)))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."notification_deliveries"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (EXISTS ( SELECT 1
   FROM better_supabase.notification_recipients r
  WHERE ((r.id = notification_deliveries.recipient_id) AND (r.user_id = ( SELECT auth.uid() AS uid)))))))
  WITH CHECK ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."notification_delivery_events"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (EXISTS ( SELECT 1
   FROM (better_supabase.notification_deliveries d
     JOIN better_supabase.notification_recipients r ON ((r.id = d.recipient_id)))
  WHERE ((d.id = notification_delivery_events.delivery_id) AND (r.user_id = ( SELECT auth.uid() AS uid)))))))
  WITH CHECK ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."notification_events"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (EXISTS ( SELECT 1
   FROM better_supabase.notification_recipients r
  WHERE ((r.event_id = notification_events.id) AND (r.user_id = ( SELECT auth.uid() AS uid)))))))
  WITH CHECK ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."notification_preferences"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (user_id = ( SELECT auth.uid() AS uid))))
  WITH
    CHECK
    (((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((user_id = ( SELECT auth.uid() AS uid)) AND ((organization_id IS NULL)
    OR (organization_id IN ( SELECT better_supabase.tenant_ids_with('notifications.read'::text) AS tenant_ids_with))))));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."notification_recipients"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (user_id = ( SELECT auth.uid() AS uid))))
  WITH CHECK (((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (user_id = ( SELECT auth.uid() AS uid))));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."notification_subscriptions"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (user_id = ( SELECT auth.uid() AS uid))))
  WITH
    CHECK
    (((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((user_id = ( SELECT auth.uid() AS uid)) AND ((organization_id IS NULL)
    OR (organization_id IN ( SELECT better_supabase.tenant_ids_with('notifications.read'::text) AS tenant_ids_with))))));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."order_lines"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('orders.read'::text)
    AS tenant_ids_with)) OR (EXISTS ( SELECT 1
   FROM better_supabase.orders o
  WHERE ((o.id = order_lines.order_id) AND (o.customer_id = ( SELECT auth.uid() AS uid))))))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."order_payments"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('orders.read'::text)
    AS tenant_ids_with)) OR (EXISTS ( SELECT 1
   FROM better_supabase.orders o
  WHERE ((o.id = order_payments.order_id) AND (o.customer_id = ( SELECT auth.uid() AS uid))))))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."order_refunds"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('orders.read'::text)
    AS tenant_ids_with)) OR (EXISTS ( SELECT 1
   FROM better_supabase.orders o
  WHERE ((o.id = order_refunds.order_id) AND (o.customer_id = ( SELECT auth.uid() AS uid))))))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."order_return_lines"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('orders.read'::text)
    AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."order_returns"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('orders.read'::text)
    AS tenant_ids_with)) OR (EXISTS ( SELECT 1
   FROM better_supabase.orders o
  WHERE ((o.id = order_returns.order_id) AND (o.customer_id = ( SELECT auth.uid() AS uid))))))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."orders"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((customer_id = ( SELECT auth.uid() AS uid)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('orders.read'::text) AS tenant_ids_with)))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."organization_settings"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (organization_id IN ( SELECT
    better_supabase.tenant_ids_with('settings.read'::text) AS tenant_ids_with)) OR
    (organization_id IN ( SELECT better_supabase.tenant_ids_with('settings.update'::text) AS tenant_ids_with))))
  WITH
    CHECK
    (((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR COALESCE(better_supabase.can('tenant'::text, organization_id,
    'settings.update'::text), false) OR (organization_id IN ( SELECT better_supabase.tenant_ids_with('settings.update'::text) AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."people"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('parties.read'::text)
    AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."person_inbox_contacts"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('parties.read'::text)
    AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."pipeline_stage_history"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('pipelines.read'::text) AS tenant_ids_with)) AND better_supabase.can_subject(subject_type, subject_id, 'read'::text))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."pipeline_stages"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('pipelines.read'::text) AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."pipeline_transitions"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('pipelines.read'::text) AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."pipelines"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('pipelines.read'::text) AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."pledges"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('donations.read'::text) AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."policies"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('controls.read'::text) AS tenant_ids_with)) OR
    (tenant_id IN ( SELECT better_supabase.tenant_ids_with('controls.acknowledge'::text) AS tenant_ids_with)))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."policy_acknowledgements"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((user_id = ( SELECT auth.uid() AS uid)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('controls.read'::text) AS tenant_ids_with)))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."post_boards"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('posts.read'::text) AS
    tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."posts"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('posts.read'::text)
    AS tenant_ids_with)) AND
    ((moderation_status = 'visible'::text) OR (author_id = ( SELECT auth.uid() AS uid)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('posts.moderate'::text) AS
    tenant_ids_with))))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."price_lists"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text)
    AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."product_categories"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text)
    AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."product_collections"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text)
    AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."product_media"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text)
    AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."product_option_values"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text)
    AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."product_options"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text)
    AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."product_prices"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text)
    AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."product_translations"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text)
    AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."product_variant_translations"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text)
    AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."product_variant_values"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text)
    AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."product_variants"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text)
    AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."products"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text)
    AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."promotion_codes"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('promotions.read'::text) AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."promotion_redemptions"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('promotions.read'::text) AS tenant_ids_with)) OR (customer_id = ( SELECT auth.uid() AS uid)))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."promotions"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('promotions.read'::text) AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."purchase_order_lines"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('inventory.read'::text) AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."purchase_orders"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('inventory.read'::text) AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."quote_lines"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (EXISTS ( SELECT 1
   FROM better_supabase.quotes x
  WHERE (x.id = quote_lines.parent_id)))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."quotes"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('quotes.read'::text)
    AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."reaction_scores"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('reactions.read'::text) AS tenant_ids_with)) AND better_supabase.reaction_subject_visible(subject_type, subject_id, tenant_id))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."reactions"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('reactions.read'::text) AS tenant_ids_with)) AND better_supabase.reaction_subject_visible(subject_type, subject_id, tenant_id)) OR
    (user_id = ( SELECT auth.uid() AS uid))))
  WITH
    CHECK
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((user_id = ( SELECT auth.uid() AS uid)) AND (actor = (( SELECT auth.uid() AS
    uid))::text) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('reactions.create'::text) AS tenant_ids_with)) AND
    better_supabase.reaction_subject_visible(subject_type, subject_id, tenant_id))));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."recurrence_rules"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."relations"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('relations.read'::text) AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."reminders"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."saved_view_preferences"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (user_id = ( SELECT auth.uid() AS uid))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."scheduled_inbox_messages"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((author_id = ( SELECT auth.uid() AS uid)) AND (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('inbox.reply'::text) AS tenant_ids_with)))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."score_model_versions"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('scores.read'::text)
    AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."score_models"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('scores.read'::text)
    AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."scores"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('scores.read'::text)
    AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."search_documents"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('search.read'::text)
    AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."segment_members"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('segments.read'::text)
    AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."segments"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('segments.read'::text)
    AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."sequence_enrollments"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('sequences.read'::text) AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."sequences"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('sequences.read'::text) AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."service_principals"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('service_principals.read'::text) AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."share_links"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."shared_views"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('views.read'::text)
    AS tenant_ids_with)) AND (((scope = 'user'::text) AND (owner_id = ( SELECT auth.uid() AS uid))) OR ((scope = 'team'::text) AND (team_id IN ( SELECT (t.t)::text AS t
   FROM better_supabase.team_ids_of(( SELECT auth.uid() AS uid)) t(t)))) OR (scope = 'tenant'::text)))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."shipment_packages"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('shipments.read'::text) AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."shipment_tracking_events"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('shipments.read'::text) AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."shipments"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('shipments.read'::text) AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."shipping_rates"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('orders.read'::text)
    AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."signature_requests"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('signatures.read'::text) AS tenant_ids_with)) OR (( SELECT auth.uid() AS uid) = ANY (signers)))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."signatures"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('signatures.read'::text) AS tenant_ids_with)) OR (signer = ( SELECT auth.uid() AS uid)))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."sla_clocks"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('sla.read'::text) AS
    tenant_ids_with)) AND better_supabase.can_subject(subject_type, subject_id, 'read'::text))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."sla_policies"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('sla.read'::text) AS
    tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."status_component_history"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('incidents.read'::text) AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."status_components"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('incidents.read'::text) AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."status_history"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR
CASE subject_type
    WHEN 'work_item'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.work_items s
      WHERE (s.id = (status_history.subject_id)::uuid)))
    ELSE false
END))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."status_pages"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('incidents.read'::text) AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."status_stages"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR
CASE subject_type
    WHEN 'work_item'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.work_items s
      WHERE (s.id = (status_stages.subject_id)::uuid)))
    ELSE false
END))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."stock_levels"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('inventory.read'::text) AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."stock_reservations"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('inventory.read'::text) AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."stock_transfer_lines"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('inventory.read'::text) AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."stock_transfers"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('inventory.read'::text) AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."storefronts"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text)
    AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."streams"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (owner_id = ( SELECT auth.uid() AS uid))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."subject_lifecycles"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR
CASE subject_type
    WHEN 'work_item'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.work_items s
      WHERE (s.id = (subject_lifecycles.subject_id)::uuid)))
    ELSE false
END))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."taggings"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."tags"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."targets"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('targets.read'::text)
    AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."team_members"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('teams.read'::text) AS
    tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."teams"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('teams.read'::text) AS
    tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."template_applications"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('templates.read'::text) AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."templates"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('templates.read'::text) AS tenant_ids_with)) OR
    ((scope = 'system'::text) AND (EXISTS ( SELECT better_supabase.tenant_ids_with('templates.read'::text) AS tenant_ids_with))))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."thread_reads"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (user_id = ( SELECT auth.uid() AS uid))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."thread_summaries"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (EXISTS ( SELECT 1
   FROM better_supabase.conversations c
  WHERE (c.id = thread_summaries.conversation_id)))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."time_entries"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((user_id = ( SELECT auth.uid() AS uid)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('time_tracking.read'::text) AS tenant_ids_with)))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."time_invoice_entries"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('billable_time.read'::text) AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."time_rates"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('billable_time.read'::text) AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."timesheets"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((user_id = ( SELECT auth.uid() AS uid)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('time_tracking.read'::text) AS tenant_ids_with)))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."trash_items"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('trash.read'::text) AS
    tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."usage_counters"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (organization_id IN ( SELECT
    better_supabase.tenant_ids_with('usage.read'::text) AS tenant_ids_with))))
  WITH CHECK ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."usage_quotas"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((organization_id IS NULL) OR (organization_id IN ( SELECT
    better_supabase.tenant_ids_with('usage.read'::text) AS tenant_ids_with)))))
  WITH CHECK ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."versions"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('versions.read'::text)
    AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."webhook_deliveries"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (organization_id IN ( SELECT
    better_supabase.tenant_ids_with('webhooks.read'::text) AS tenant_ids_with))))
  WITH CHECK ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."webhook_endpoints"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (organization_id IN ( SELECT
    better_supabase.tenant_ids_with('webhooks.read'::text) AS tenant_ids_with)) OR
    (organization_id IN ( SELECT better_supabase.tenant_ids_with('webhooks.manage'::text) AS tenant_ids_with))))
  WITH
    CHECK
    (((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (organization_id IN ( SELECT
    better_supabase.tenant_ids_with('webhooks.manage'::text) AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."work_item_assignees"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('work_items.read'::text) AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."work_item_checklist_items"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('work_items.read'::text) AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."work_items"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('work_items.read'::text) AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."work_order_parts"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('dispatch.read'::text)
    AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."work_orders"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((technician_id = ( SELECT auth.uid() AS uid)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('dispatch.read'::text) AS tenant_ids_with)))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."work_projects"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('work_items.read'::text) AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."workflow_credentials"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('workflow.read'::text)
    AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."workflow_definitions"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('workflow.read'::text) AS tenant_ids_with)) OR
    ((scope = 'system'::text) AND (EXISTS ( SELECT better_supabase.tenant_ids_with('workflow.read'::text) AS tenant_ids_with))))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."workflow_opt_outs"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('workflow.read'::text)
    AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."workflow_runs"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((actor_id = ( SELECT auth.uid() AS uid)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('workflow.read'::text) AS tenant_ids_with)))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."workflow_schedules"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('workflow.read'::text)
    AS tenant_ids_with))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "public"."client_notes"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "public"."projects"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope" ON "public"."tasks"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

REVOKE ALL ON FUNCTION "api"."as_column_type"(text, anyelement) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."as_column_type"(text, anyelement) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."as_column_type"(text, anyelement) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."as_column_type"(text, anyelement) TO "anon", "authenticated", "service_role";
