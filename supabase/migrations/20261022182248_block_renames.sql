SET local check_function_bodies = off;

DROP POLICY "collections_read" ON "better_supabase"."product_collections";

ALTER TABLE "better_supabase"."applications"
  DROP CONSTRAINT "applications_job_id_fkey";

ALTER TABLE "better_supabase"."collection_products"
  DROP CONSTRAINT "collection_products_collection_id_fkey";

ALTER TABLE "better_supabase"."job_openings"
  DROP CONSTRAINT "jobs_pkey";

ALTER TABLE "better_supabase"."job_openings"
  DROP CONSTRAINT "jobs_status_check";

ALTER TABLE "better_supabase"."job_openings"
  DROP CONSTRAINT "jobs_title_check";

ALTER TABLE "better_supabase"."product_collections"
  DROP CONSTRAINT "collections_check";

ALTER TABLE "better_supabase"."product_collections"
  DROP CONSTRAINT "collections_kind_check";

ALTER TABLE "better_supabase"."product_collections"
  DROP CONSTRAINT "collections_pkey";

ALTER TABLE "better_supabase"."product_collections"
  DROP CONSTRAINT "collections_slug_check";

ALTER TABLE "better_supabase"."product_collections"
  DROP CONSTRAINT "collections_tenant_id_slug_key";

ALTER TABLE "better_supabase"."product_collections"
  DROP CONSTRAINT "collections_title_check";

DROP FUNCTION "better_supabase"."passes_subject_merge"(text, text, text);

CREATE OR REPLACE FUNCTION better_supabase.acknowledge_policy (
  policy_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."policies"%rowtype;
  v_me uuid := auth.uid();
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."policies" x where x."id" = acknowledge_policy.policy_id;
  if not found then
    raise exception 'policy not found' using errcode = 'P0002', hint = 'POLICY_NOT_FOUND';
  end if;
  if v_me is null or not coalesce(better_supabase.can('tenant', v_row."tenant_id", 'controls.acknowledge'), false) then
    raise exception 'not allowed to acknowledge policies' using errcode = '42501', hint = 'POLICY_FORBIDDEN';
  end if;
  if v_row."current_version_id" is null or v_row."archived_at" is not null then
    raise exception 'the policy has no published version to acknowledge' using errcode = '55000', hint = 'POLICY_NOT_PUBLISHED';
  end if;
  insert into "better_supabase"."policy_acknowledgements" ("tenant_id", "policy_id", "version_id", "user_id")
  values (v_row."tenant_id", v_row."id", v_row."current_version_id", v_me)
  on conflict ("policy_id", "version_id", "user_id") do nothing;
  if found then
    perform "better_supabase".emit_event('policy.acknowledged', jsonb_build_object('organizationId', v_row."tenant_id", 'policyId', v_row."id", 'versionId', v_row."current_version_id", 'userId', v_me), 'policies/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/compliance');
  perform better_supabase.audit_event(
    event_type => 'policy.acknowledged',
    category => 'data',
    target_type => 'policy',
    record_id => v_row."id"::text,
    summary => 'acknowledged policy ' || v_row."title" || ' version ' || v_row."version_number"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'policyId', v_row."id", 'versionId', v_row."current_version_id", 'userId', v_me)
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'ownerId', v_row."owner_id", 'requiresAcknowledgement', v_row."requires_acknowledgement", 'versionId', v_row."current_version_id", 'versionNumber', v_row."version_number", 'publishedAt', v_row."published_at", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."policy_acknowledgements" ack where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."policy_acknowledgements" ack join "public"."memberships" am on am."organization_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id"), 'memberCount', (select count(*) from "public"."memberships" pm where pm."organization_id" = v_row."tenant_id"));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.add_control_evidence (
  control_id    uuid,
  attachment_id uuid DEFAULT NULL::uuid,
  note          text DEFAULT NULL::text,
  valid_until   date DEFAULT NULL::date,
  task_id       uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_control "better_supabase"."controls"%rowtype;
  v_task "better_supabase"."evidence_tasks"%rowtype;
  v_row "better_supabase"."control_evidence"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_control from "better_supabase"."controls" x where x."id" = add_control_evidence.control_id;
  if not found then
    raise exception 'control not found' using errcode = 'P0002', hint = 'CONTROL_NOT_FOUND';
  end if;
  if add_control_evidence.task_id is not null then
    select * into v_task from "better_supabase"."evidence_tasks" x
      where x."id" = add_control_evidence.task_id and x."control_id" = v_control."id"
      for update;
    if not found then
      raise exception 'the evidence task isn''t a task of this control' using errcode = 'P0002', hint = 'EVIDENCE_TASK_NOT_FOUND';
    end if;
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_control."tenant_id", 'controls.collect'), false)) or (v_task."assignee_id" is not null and v_task."assignee_id" = auth.uid())) then
    raise exception 'not allowed to collect evidence' using errcode = '42501', hint = 'CONTROLS_FORBIDDEN';
  end if;
  if add_control_evidence.attachment_id is null and nullif(trim(add_control_evidence.note), '') is null then
    raise exception 'evidence needs an attachment or a note' using errcode = '22023', hint = 'CONTROLS_INVALID';
  end if;
  if add_control_evidence.attachment_id is not null and not exists (
    select 1 from "better_supabase"."attachments" a
    where a."id" = add_control_evidence.attachment_id
      and a."organization_id" = v_control."tenant_id"
  ) then
    raise exception 'the attachment isn''t a file in this organization' using errcode = '22023', hint = 'CONTROLS_INVALID';
  end if;
  insert into "better_supabase"."control_evidence" ("tenant_id", "control_id", "task_id", "attachment_id", "note", "collected_by", "valid_until")
  values (v_control."tenant_id", v_control."id", v_task."id", add_control_evidence.attachment_id,
    nullif(trim(add_control_evidence.note), ''), auth.uid(),
    coalesce(add_control_evidence.valid_until, current_date + v_task."interval_days"))
  returning * into v_row;
  if v_task."id" is not null then
    update "better_supabase"."evidence_tasks" x set "due_on" = current_date + x."interval_days", "last_collected_at" = now(),
      "notified_for" = null, "updated_at" = now()
      where x."id" = v_task."id";
  end if;
  perform "better_supabase".emit_event('control.evidence_added', jsonb_build_object('organizationId', v_row."tenant_id", 'controlId', v_row."control_id", 'evidenceId', v_row."id", 'evidenceTaskId', v_row."task_id"), 'controls/' || v_row."control_id"::text, (v_row."tenant_id")::text, null, 'better-supabase/compliance');
  perform better_supabase.audit_event(
    event_type => 'control.evidence_added',
    category => 'data',
    target_type => 'control',
    record_id => v_row."control_id"::text,
    summary => 'collected evidence for control ' || v_control."code",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'controlId', v_row."control_id", 'evidenceId', v_row."id", 'evidenceTaskId', v_row."task_id")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'controlId', v_row."control_id", 'evidenceTaskId', v_row."task_id", 'attachmentId', v_row."attachment_id", 'note', v_row."note", 'collectedBy', v_row."collected_by", 'collectedAt', v_row."collected_at", 'validUntil', v_row."valid_until", 'valid', (v_row."valid_until" is null or v_row."valid_until" >= current_date));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.add_to_collection (
  collection uuid,
  product    uuid,
  rank       text
)
  RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_kind text;
  v_last text;
  v_rank text := add_to_collection.rank;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."kind" into v_tenant, v_kind from "better_supabase"."product_collections" x where x."id" = add_to_collection.collection for update;
  if v_tenant is null then
    raise exception 'collection not found' using errcode = 'P0002', hint = 'CATALOG_COLLECTION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  if v_kind <> 'manual' then
    raise exception 'a rule collection picks its products from its rule' using errcode = '22023', hint = 'CATALOG_COLLECTION_RULE';
  end if;
  if not exists (select 1 from "better_supabase"."products" x where x."id" = add_to_collection.product and x."tenant_id" = v_tenant) then
    raise exception 'product not found' using errcode = 'P0002', hint = 'CATALOG_PRODUCT_NOT_FOUND';
  end if;
  if v_rank is not null and v_rank !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'not a rank key' using errcode = '22023', hint = 'CATALOG_RANK_INVALID';
  end if;
  if v_rank is null then
    select max(x."rank" collate "C") into v_last from "better_supabase"."collection_products" x where x."collection_id" = add_to_collection.collection;
    v_rank := case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end;
  end if;
  insert into "better_supabase"."collection_products" as x ("tenant_id", "collection_id", "product_id", "rank")
  values (v_tenant, add_to_collection.collection, add_to_collection.product, v_rank)
  on conflict ("collection_id", "product_id") do update set "rank" = excluded."rank";
  return v_rank;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.admission_passes_subject_merge (
  subject_table text,
  keep          text,
  drop          text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_type text;
  v_keep text := keep;
  v_drop text := drop;
begin
  for v_type in select unnest(case subject_table when 'better_supabase.messages' then array['message'] when 'better_supabase.conversations' then array['conversation'] when 'better_supabase.channels' then array['channel'] when 'better_supabase.companies' then array['company'] when 'better_supabase.people' then array['person'] when 'better_supabase.deals' then array['deal'] when 'better_supabase.courses' then array['course'] when 'better_supabase.posts' then array['post'] when 'better_supabase.engagements' then array['engagement'] when 'better_supabase.work_items' then array['work_item'] when 'better_supabase.employees' then array['employee'] when 'better_supabase.ledger_accounts' then array['ledger_account'] when 'better_supabase.products' then array['product'] when 'better_supabase.product_variants' then array['product_variant'] when 'better_supabase.calendar_events' then array['calendar_event'] when 'better_supabase.assets' then array['asset'] when 'better_supabase.asset_locations' then array['asset_location'] when 'better_supabase.lease_agreements' then array['lease'] when 'better_supabase.maintenance_requests' then array['maintenance_request'] when 'better_supabase.expense_reports' then array['expense_report'] when 'better_supabase.expense_lines' then array['expense_line'] when 'better_supabase.donation_funds' then array['donation_fund'] when 'better_supabase.work_orders' then array['work_order'] when 'better_supabase.shipments' then array['shipment'] when 'better_supabase.contracts' then array['contract'] when 'better_supabase.controls' then array['control'] when 'better_supabase.policies' then array['policy'] when 'better_supabase.incidents' then array['incident'] when 'better_supabase.documents' then array['document'] when 'public.customers' then array['customer'] when 'better_supabase.drive_nodes' then array['drive_node'] when 'better_supabase.applications' then array['application'] when 'public.projects' then array['project'] when 'public.tasks' then array['task'] else '{}'::text[] end) loop
    update "better_supabase"."passes" x set "subject_id" = v_keep where x."subject_type" = v_type and x."subject_id" = v_drop;
  end loop;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.apply_to_job (
  job       uuid,
  candidate jsonb,
  source    text,
  owner     uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_job "better_supabase"."job_openings";
  v_row "better_supabase"."applications";
  v_type text := coalesce(apply_to_job.candidate ->> 'type', 'person');
  v_id text := apply_to_job.candidate ->> 'id';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_job from "better_supabase"."job_openings" x where x."id" = apply_to_job.job;
  if v_job."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_job."tenant_id", 'hiring.write'), false)) then
    raise exception 'no such job you can add applications to' using errcode = 'P0002', hint = 'HIRING_JOB_NOT_FOUND';
  end if;
  if v_job."status" <> 'open' then
    raise exception 'the job isn''t open' using errcode = '55000', hint = 'HIRING_JOB_NOT_OPEN';
  end if;
  if v_id is null or not (case v_type
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'maintenance_request' then exists (select 1 from "better_supabase"."maintenance_requests" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_id)::uuid and s."organization_id"::text = v_job."tenant_id"::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_id)::uuid and s."organization_id"::text = v_job."tenant_id"::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_id)::uuid and s."organization_id"::text = v_job."tenant_id"::text)
      else false
    end and "better_supabase"."can_subject"(v_type, v_id, 'read')) then
    raise exception 'the candidate is unknown or not readable in this organization' using errcode = '42501', hint = 'HIRING_CANDIDATE_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."applications" x
  where x."job_id" = v_job."id" and x."candidate_type" = v_type and x."candidate_id" = v_id;
  if v_row."id" is not null then
    return to_jsonb(v_row);
  end if;
  insert into "better_supabase"."applications" ("tenant_id", "job_id", "candidate_type", "candidate_id", "source", "owner_user_id")
  values (v_job."tenant_id", v_job."id", v_type, v_id, nullif(trim(apply_to_job.source), ''), coalesce(apply_to_job.owner, auth.uid()))
  returning * into v_row;
  perform "better_supabase".emit_event('application.created', jsonb_build_object('organizationId', v_row."tenant_id", 'applicationId', v_row."id", 'subjectType', 'application', 'subjectId', v_row."id"::text, 'jobId', v_row."job_id", 'candidateType', v_row."candidate_type", 'candidateId', v_row."candidate_id"), 'applications/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/hiring');
  return to_jsonb(v_row);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.archive_company (
  id       uuid,
  archived boolean
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_name text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."name" into v_tenant, v_name from "better_supabase"."companies" x where x."id" = archive_company.id;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'parties.write'), false)) then
    raise exception 'not allowed to change companies and people' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  begin
    update "better_supabase"."companies" x set "archived_at" = case when archive_company.archived then coalesce(x."archived_at", now()) end, "updated_at" = now()
    where x."id" = archive_company.id;
  exception when unique_violation then
    raise exception 'another company has this domain' using errcode = '23505', hint = 'PARTY_DOMAIN_TAKEN';
  end;
  if archive_company.archived then
    perform "better_supabase".emit_event('company.archived', jsonb_build_object('organizationId', v_tenant, 'companyId', archive_company.id, 'name', v_name), 'companies/' || archive_company.id::text, (v_tenant::text)::text, null, 'better-supabase/contacts');
  end if;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.archive_person (
  id       uuid,
  archived boolean
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_name text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."name" into v_tenant, v_name from "better_supabase"."people" x where x."id" = archive_person.id;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'parties.write'), false)) then
    raise exception 'not allowed to change companies and people' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  begin
    update "better_supabase"."people" x set "archived_at" = case when archive_person.archived then coalesce(x."archived_at", now()) end, "updated_at" = now()
    where x."id" = archive_person.id;
  exception when unique_violation then
    raise exception 'another person has this email' using errcode = '23505', hint = 'PARTY_EMAIL_TAKEN';
  end;
  if archive_person.archived then
    perform "better_supabase".emit_event('person.archived', jsonb_build_object('organizationId', v_tenant, 'personId', archive_person.id, 'name', v_name), 'persons/' || archive_person.id::text, (v_tenant::text)::text, null, 'better-supabase/contacts');
  end if;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.archive_work_item (
  work_item uuid,
  archived  boolean
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."work_items";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "better_supabase"."work_items" x set "archived_at" = case when archive_work_item.archived then coalesce(x."archived_at", now()) end
  where x."id" = archive_work_item.work_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'work_items.write'), false))
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  if archive_work_item.archived then
    perform "better_supabase".emit_event('work_item.archived', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title"), 'work-items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  end if;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.attach_engagement_recording (
  engagement uuid,
  file       uuid,
  language   text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_type text;
  v_recording uuid;
  v_subjects jsonb;
  v_first jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."type" into v_tenant, v_type
  from "better_supabase"."engagements" x where x."id" = attach_engagement_recording.engagement and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'engagements.manage'), false));
  if v_tenant is null then
    raise exception 'no such engagement you can edit' using errcode = 'P0002', hint = 'ENGAGEMENT_NOT_FOUND';
  end if;
  if not exists (
    select 1 from "better_supabase"."ai_files" fx
    where fx."id" = attach_engagement_recording.file
      and fx."organization_id"::text = v_tenant::text
      and fx."status" = 'ready'
      and (auth.role() = 'service_role' or fx."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_tenant, 'engagements.manage'), false))
  ) then
    raise exception 'no such ready file in this organization' using errcode = 'P0002', hint = 'AI_FILE_NOT_FOUND';
  end if;
  insert into "better_supabase"."engagement_recordings" ("tenant_id", "engagement_id", "file_id", "filename", "media_type", "language", "created_by")
  select v_tenant, attach_engagement_recording.engagement, fx."id", fx."filename", fx."media_type", nullif(trim(attach_engagement_recording.language), ''), auth.uid()
  from "better_supabase"."ai_files" fx where fx."id" = attach_engagement_recording.file
  on conflict ("engagement_id", "file_id") do nothing
  returning "id" into v_recording;
  if v_recording is null then
    raise exception 'the file is already a recording of this engagement' using errcode = '23505', hint = 'ENGAGEMENT_RECORDING_EXISTS';
  end if;
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = attach_engagement_recording.engagement), '[]'::jsonb);
  v_first := v_subjects -> 0;
  perform "better_supabase".emit_event('engagement.recorded', jsonb_build_object('organizationId', v_tenant, 'engagementId', attach_engagement_recording.engagement, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects, 'recordingId', v_recording), 'engagements/' || attach_engagement_recording.engagement::text, (v_tenant::text)::text, null, 'better-supabase/activities');
  perform "better_supabase"."enqueue_job"(queue => 'engagements.transcribe', payload => jsonb_build_object('recordingId', v_recording), dedupe_key => 'engagements.transcribe:' || v_recording::text, dedupe_running => false);
  return (select jsonb_build_object('id', rx."id", 'organizationId', rx."tenant_id", 'engagementId', rx."engagement_id", 'fileId', rx."file_id", 'filename', rx."filename", 'mediaType', rx."media_type", 'status', rx."status", 'language', rx."language", 'durationSeconds', rx."duration_seconds", 'error', rx."error", 'model', rx."model", 'segmentCount', (select count(*)::integer from "better_supabase"."engagement_transcript_segments" sc where sc."recording_id" = rx."id"), 'createdBy', rx."created_by", 'createdAt', rx."created_at", 'transcribedAt', rx."transcribed_at") from "better_supabase"."engagement_recordings" rx where rx."id" = v_recording);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.book_with_credit (
  pass_id   uuid,
  service   uuid,
  resource  uuid,
  starts_at timestamp with time zone,
  customer  jsonb                    DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_pass "better_supabase"."passes"%rowtype;
  v_tenant uuid;
  v_booking jsonb;
  v_entry "better_supabase"."pass_credit_entries"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_pass from "better_supabase"."passes" x where x."id" = book_with_credit.pass_id for update;
  if not found or not (v_pass."holder_user_id" = auth.uid() or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_pass."tenant_id", 'passes.manage'), false))) then
    raise exception 'pass not found' using errcode = 'P0002', hint = 'PASS_NOT_FOUND';
  end if;
  if v_pass."status" <> 'active' then
    raise exception 'the pass is revoked' using errcode = '55000', hint = 'PASS_REVOKED';
  end if;
  if v_pass."uses_allowed" is null or v_pass."booking_id" is not null then
    raise exception 'only a pass with a number of uses and no booking of its own pays for bookings' using errcode = '22023', hint = 'PASS_NOT_CREDITS';
  end if;
  if v_pass."resource_id" is not null and v_pass."resource_id" <> book_with_credit.resource then
    raise exception 'the pass is for another resource' using errcode = '22023', hint = 'PASS_WRONG_RESOURCE';
  end if;
  if book_with_credit.starts_at < v_pass."valid_from" or (v_pass."valid_until" is not null and book_with_credit.starts_at >= v_pass."valid_until") then
    raise exception 'the pass is not valid when the class starts' using errcode = '22023', hint = 'PASS_NOT_VALID';
  end if;
  if v_pass."uses" >= v_pass."uses_allowed" then
    raise exception 'the pass has no credits left' using errcode = '55000', hint = 'PASS_CREDITS_USED_UP';
  end if;
  select sv."tenant_id" into v_tenant from "better_supabase"."booking_services" sv where sv."id" = book_with_credit.service;
  if v_tenant is distinct from v_pass."tenant_id" then
    raise exception 'the service does not exist in the pass''s organization' using errcode = 'P0002', hint = 'PASS_BOOKING_NOT_FOUND';
  end if;
  v_booking := "better_supabase"."hold_booking"(book_with_credit.service, book_with_credit.resource, book_with_credit.starts_at,
    coalesce(book_with_credit.customer, '{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object('userId', v_pass."holder_user_id", 'name', v_pass."holder_name", 'email', v_pass."holder_email")), true);
  insert into "better_supabase"."pass_credit_entries" ("tenant_id", "pass_id", "booking_id", "delta", "reason", "created_by")
  values (v_pass."tenant_id", v_pass."id", (v_booking ->> 'id')::uuid, -1, 'booking', auth.uid())
  returning * into v_entry;
  update "better_supabase"."passes" x set "uses" = x."uses" + 1, "updated_at" = now()
  where x."id" = v_pass."id";
  perform "better_supabase".emit_event('pass.credit_used', jsonb_build_object('organizationId', v_entry."tenant_id"::text, 'id', v_entry."pass_id", 'entryId', v_entry."id", 'bookingId', v_entry."booking_id"), 'passes/' || v_entry."pass_id"::text, (v_entry."tenant_id")::text, null, 'better-supabase/admission-passes');
  perform better_supabase.audit_event(
    event_type => 'pass.credit_used',
    category => 'access',
    target_type => 'pass',
    record_id => v_entry."pass_id"::text,
    summary => 'booked with a credit of pass',
    tenant => (v_entry."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_entry."tenant_id"::text, 'id', v_entry."pass_id", 'entryId', v_entry."id", 'bookingId', v_entry."booking_id")
  );
  return (v_booking - 'accessToken') || jsonb_build_object('passId', v_pass."id", 'creditsLeft', v_pass."uses_allowed" - v_pass."uses" - 1);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_booking_engagement()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_ref text := 'booking:' || new."id"::text;
  v_tenant uuid := new."tenant_id";
  v_id uuid;
  v_inserted boolean;
  v_title text;
  v_owner uuid := new."created_by";
  v_person uuid;
  v_person_owner uuid;
  v_subjects jsonb;
  v_first jsonb;
begin
  if new."status" = 'confirmed' then
    if tg_op = 'UPDATE' and old."status" = 'confirmed' and old."during" = new."during" then
      return null;
    end if;
    select p."id", p."owner_user_id" into v_person, v_person_owner
    from "better_supabase"."people" p
    where p."tenant_id" = v_tenant and p."archived_at" is null and p."merged_into" is null
      and ((new."customer_user_id" is not null and p."user_id" = new."customer_user_id")
        or (new."customer_email" is not null and lower(p."email") = lower(new."customer_email")))
    order by (new."customer_user_id" is not null and p."user_id" = new."customer_user_id") desc, p."created_at"
    limit 1;
    v_owner := coalesce(v_owner, v_person_owner);
    select left(coalesce(sv."name", 'Booking') || coalesce(' with ' || nullif(trim(new."customer_name"), ''), ''), 500)
    into v_title
    from "better_supabase"."booking_services" sv where sv."id" = new."service_id";
    insert into "better_supabase"."engagements" ("tenant_id", "type", "title", "body", "owner_user_id", "due_at", "duration_seconds", "external_ref", "created_by")
    values (v_tenant, 'meeting', coalesce(v_title, 'Booking'), new."notes", v_owner, lower(new."during"),
      extract(epoch from upper(new."during") - lower(new."during"))::integer, v_ref, new."created_by")
    on conflict ("tenant_id", "external_ref") where "external_ref" is not null do update set
      "due_at" = excluded."due_at", "duration_seconds" = excluded."duration_seconds",
      "done_at" = null, "outcome" = null, "updated_at" = now()
    returning "id", (xmax = 0) into v_id, v_inserted;
    if v_person is not null then
      insert into "better_supabase"."engagement_subjects" ("tenant_id", "engagement_id", "subject_type", "subject_id", "position")
      values (v_tenant, v_id, 'person', v_person::text, 1)
      on conflict do nothing;
      insert into "better_supabase"."engagement_subjects" ("tenant_id", "engagement_id", "subject_type", "subject_id", "position")
      select v_tenant, v_id, 'company', c."id"::text, 2
      from "better_supabase"."company_people" k
      join "better_supabase"."companies" c on c."id" = k."company_id"
      where k."person_id" = v_person and c."archived_at" is null
      order by k."is_primary" desc, k."created_at"
      limit 1
      on conflict do nothing;
    end if;
    v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = v_id), '[]'::jsonb);
    v_first := v_subjects -> 0;
    if v_inserted then
      perform "better_supabase".emit_event('engagement.logged', jsonb_build_object('organizationId', v_tenant, 'engagementId', v_id, 'type', 'meeting', 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects), 'engagements/' || v_id::text, (v_tenant::text)::text, null, 'better-supabase/activities');
    else
      perform "better_supabase".emit_event('engagement.updated', jsonb_build_object('organizationId', v_tenant, 'engagementId', v_id, 'type', 'meeting', 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects), 'engagements/' || v_id::text, (v_tenant::text)::text, null, 'better-supabase/activities');
    end if;
  elsif new."status" = 'cancelled' and tg_op = 'UPDATE' and old."status" = 'confirmed' then
    update "better_supabase"."engagements" x set
      "done_at" = coalesce(new."cancelled_at", now()),
      "outcome" = left('cancelled' || coalesce(': ' || nullif(trim(new."cancel_reason"), ''), ''), 500),
      "updated_at" = now()
    where x."tenant_id" = v_tenant and x."external_ref" = v_ref and x."done_at" is null
    returning x."id" into v_id;
    if v_id is not null then
    v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = v_id), '[]'::jsonb);
    v_first := v_subjects -> 0;
      perform "better_supabase".emit_event('engagement.completed', jsonb_build_object('organizationId', v_tenant, 'engagementId', v_id, 'type', 'meeting', 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects), 'engagements/' || v_id::text, (v_tenant::text)::text, null, 'better-supabase/activities');
    end if;
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_work_item_guard()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if new."parent_id" is not null and (tg_op = 'INSERT' or new."parent_id" is distinct from old."parent_id") then
    if exists (
      with recursive up(id, depth) as (
        select new."parent_id", 1
        union all
        select x."parent_id", up.depth + 1 from "better_supabase"."work_items" x join up on x."id" = up.id
        where x."parent_id" is not null and up.depth < 100
      )
      select 1 from up where up.id = new."id"
    ) then
      raise exception 'an item can''t sit under itself' using errcode = '23514', hint = 'WORK_ITEM_PARENT_CYCLE';
    end if;
    if not exists (select 1 from "better_supabase"."work_items" x where x."id" = new."parent_id" and x."tenant_id" = new."tenant_id") then
      raise exception 'the parent is in another organization' using errcode = '22023', hint = 'WORK_ITEM_PARENT_INVALID';
    end if;
  end if;
  if tg_op = 'UPDATE' and old."locked" and not (auth.role() = 'service_role') and (new."start_at" is distinct from old."start_at" or new."end_at" is distinct from old."end_at" or new."due_at" is distinct from old."due_at") then
    raise exception 'the item is locked; its dates can''t change' using errcode = '55000', hint = 'WORK_ITEM_LOCKED';
  end if;
  if tg_op = 'INSERT' then
    if new."state" in ('completed', 'canceled') then
      new."closed_at" := now();
      new."close_reason" := coalesce(new."close_reason", case new."state" when 'completed' then 'completed' else 'not_planned' end);
    end if;
    return new;
  end if;
  if new."state" is distinct from old."state" then
    if new."state" in ('completed', 'canceled') and old."state" not in ('completed', 'canceled') then
      new."closed_at" := now();
      new."close_reason" := coalesce(new."close_reason", case new."state" when 'completed' then 'completed' else 'not_planned' end);
      if new."state" = 'completed' and new."progress" is not null then
        new."progress" := 100;
      end if;
      perform "better_supabase".emit_event('work_item.closed', jsonb_build_object('organizationId', new."tenant_id", 'workItemId', new."id", 'subjectType', 'work_item', 'subjectId', new."id"::text, 'title', new."title", 'state', new."state", 'closeReason', new."close_reason"), 'work-items/' || new."id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/tasks');
    elsif not (new."state" in ('completed', 'canceled')) and old."state" in ('completed', 'canceled') then
      new."closed_at" := null;
      new."close_reason" := null;
      perform "better_supabase".emit_event('work_item.reopened', jsonb_build_object('organizationId', new."tenant_id", 'workItemId', new."id", 'subjectType', 'work_item', 'subjectId', new."id"::text, 'title', new."title"), 'work-items/' || new."id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/tasks');
    end if;
  end if;
  new."updated_at" := now();
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bulk_step (
  run_id uuid,
  size   integer
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_run "better_supabase"."bulk_runs"%rowtype;
  v_role text := current_user;
  v_claims text := current_setting('request.jwt.claims', true);
  v_size integer := least(greatest(coalesce(bulk_step.size, 200), 1), 500);
  v_chunk text[];
  v_id text;
  v_ok integer := 0;
  v_failed integer := 0;
  v_results jsonb := '[]'::jsonb;
  v_message text;
  v_hint text;
  v_state text;
  v_allowed boolean;
  v_status text;
  v_done boolean;
begin
  select * into v_run from "better_supabase"."bulk_runs" r where r."id" = bulk_step.run_id for update;
  if not found then
    raise exception 'bulk run not found' using errcode = 'P0002', hint = 'BULK_RUN_NOT_FOUND';
  end if;
  if v_run."status" in ('completed', 'failed') then
    return jsonb_build_object('id', v_run."id", 'status', v_run."status", 'done', true);
  end if;
  v_chunk := v_run."ids"[v_run."position" + 1 : v_run."position" + v_size];
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_run."created_by", 'role', 'authenticated', 'aud', 'authenticated')::text, true);
  set local role authenticated;
  v_allowed := coalesce(better_supabase.can('tenant', v_run."tenant_id", 'bulk.run'), false);
  if v_allowed then
    foreach v_id in array v_chunk loop
    begin
      perform "better_supabase"."bulk_row"(v_run."tenant_id", v_run."subject_type", v_id, v_run."action", v_run."args");
      v_ok := v_ok + 1;
      v_results := v_results || jsonb_build_array(jsonb_build_object('id', v_id, 'ok', true));
    exception when others then
      get stacked diagnostics v_message = message_text, v_hint = pg_exception_hint, v_state = returned_sqlstate;
      if false then
        raise exception using message = v_message, hint = coalesce(v_hint, ''), errcode = v_state;
      end if;
      v_failed := v_failed + 1;
      v_results := v_results || jsonb_build_array(jsonb_build_object('id', v_id, 'ok', false, 'error', jsonb_build_object('code', nullif(v_hint, ''), 'message', v_message, 'sqlstate', v_state)));
    end;
  end loop;
  end if;
  execute format('set local role %I', v_role);
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  v_done := not v_allowed or v_run."position" + cardinality(coalesce(v_chunk, array[]::text[])) >= cardinality(v_run."ids");
  v_status := case when not v_allowed then 'failed' when v_done then 'completed' else 'running' end;
  update "better_supabase"."bulk_runs" set
    "position" = case when v_allowed then "position" + cardinality(coalesce(v_chunk, array[]::text[])) else "position" end,
    "succeeded" = "succeeded" + v_ok,
    "failed" = "failed" + v_failed,
    "results" = "results" || v_results,
    "status" = v_status,
    "finished_at" = case when v_done then now() else null end
  where "id" = v_run."id"
  returning * into v_run;
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send(jsonb_build_object('id', v_run."id", 'status', v_status, 'position', v_run."position", 'total', cardinality(v_run."ids"), 'succeeded', v_run."succeeded", 'failed', v_run."failed"), 'progress', 'bulk:' || v_run."id"::text, true);
  end if;
  if v_done then
    perform "better_supabase".emit_event('bulk_run.completed', jsonb_build_object('organizationId', v_run."tenant_id", 'id', v_run."id", 'kind', v_run."action", 'status', v_status, 'count', cardinality(v_run."ids"), 'failed', v_run."failed"), 'bulk-runs/' || v_run."id"::text, (v_run."tenant_id")::text, null, 'better-supabase/bulk-actions');
  end if;
  return jsonb_build_object('id', v_run."id", 'status', v_status, 'position', v_run."position", 'total', cardinality(v_run."ids"), 'succeeded', v_run."succeeded", 'failed', v_run."failed", 'done', v_done);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.check_in_pass (
  pass_id     uuid,
  nonce       text DEFAULT NULL::text,
  method      text DEFAULT 'qr'::text,
  gate        text DEFAULT NULL::text,
  resource_id uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_pass "better_supabase"."passes"%rowtype;
  v_row "better_supabase"."pass_check_ins"%rowtype;
  v_reason text;
  v_resource uuid;
  v_capacity integer;
  v_booking "better_supabase"."bookings"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if check_in_pass.method is null or check_in_pass.method not in ('qr', 'nfc', 'manual') then
    raise exception 'method is qr, nfc or manual' using errcode = '22023', hint = 'PASS_METHOD_INVALID';
  end if;
  select * into v_pass from "better_supabase"."passes" x where x."id" = check_in_pass.pass_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_pass."tenant_id", 'passes.check_in'), false)) then
    raise exception 'pass not found' using errcode = 'P0002', hint = 'PASS_NOT_FOUND';
  end if;
  v_resource := coalesce(check_in_pass.resource_id, v_pass."resource_id");
  v_reason := case
    when check_in_pass.method <> 'manual' and check_in_pass.nonce is distinct from v_pass."nonce" then 'invalid'
    when v_pass."status" = 'revoked' then 'revoked'
    when now() < v_pass."valid_from" then 'not_yet_valid'
    when v_pass."valid_until" is not null and now() >= v_pass."valid_until" then 'expired'
    when v_pass."uses_allowed" is not null and v_pass."uses" >= v_pass."uses_allowed" then 'used_up'
    when check_in_pass.resource_id is not null and v_pass."resource_id" is not null
      and check_in_pass.resource_id <> v_pass."resource_id" then 'wrong_resource'
  end;
  if v_reason is null and v_pass."booking_id" is not null then
    select * into v_booking from "better_supabase"."bookings" bk where bk."id" = v_pass."booking_id";
    if not found or v_booking."status" = 'cancelled'
      or (v_booking."status" = 'hold' and v_booking."hold_expires_at" <= now()) then
      v_reason := 'booking_cancelled';
    elsif v_booking."status" = 'hold' then
      v_reason := 'booking_unconfirmed';
    elsif now() < lower(v_booking."during") - '1 hour'::interval
      or now() >= upper(v_booking."during") then
      v_reason := 'outside_window';
    end if;
  end if;
  if v_reason is null and v_pass."booking_id" is null and v_resource is not null then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('bsb:passes:' || v_resource::text, 0));
    select rs."capacity" into v_capacity from "better_supabase"."booking_resources" rs
      where rs."id" = v_resource and rs."tenant_id" = v_pass."tenant_id";
    if v_capacity is null then
      v_reason := 'wrong_resource';
    elsif ((select count(*) from "better_supabase"."bookings" bk
      where bk."resource_id" = v_resource and (bk."status" = 'confirmed' or (bk."status" = 'hold' and bk."hold_expires_at" > now())) and bk."during" @> now())
      + (select count(*) from "better_supabase"."pass_check_ins" y
      where y."resource_id" = v_resource and y."admitted" and y."booking_id" is null
        and y."created_at" > now() - '2 hours'::interval)) >= v_capacity then
      v_reason := 'full';
    end if;
  end if;
  insert into "better_supabase"."pass_check_ins" ("tenant_id", "pass_id", "resource_id", "booking_id", "gate", "method", "admitted", "reason", "checked_in_by")
  values (v_pass."tenant_id", v_pass."id", v_resource, v_pass."booking_id", check_in_pass.gate, check_in_pass.method, v_reason is null, v_reason, auth.uid())
  returning * into v_row;
  if v_reason is null then
    update "better_supabase"."passes" x set "uses" = x."uses" + 1, "updated_at" = now()
      where x."id" = v_pass."id"
      returning * into v_pass;
    perform "better_supabase".emit_event('pass.admitted', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."pass_id", 'checkInId', v_row."id", 'resourceId', v_row."resource_id", 'bookingId', v_row."booking_id"), 'passes/' || v_row."pass_id"::text, (v_row."tenant_id")::text, null, 'better-supabase/admission-passes');
  else
    perform "better_supabase".emit_event('pass.rejected', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."pass_id", 'checkInId', v_row."id", 'resourceId', v_row."resource_id", 'bookingId', v_row."booking_id", 'reason', v_row."reason"), 'passes/' || v_row."pass_id"::text, (v_row."tenant_id")::text, null, 'better-supabase/admission-passes');
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id"::text, 'passId', v_row."pass_id", 'resourceId', v_row."resource_id", 'bookingId', v_row."booking_id", 'gate', v_row."gate", 'method', v_row."method", 'admitted', v_row."admitted", 'reason', v_row."reason", 'checkedInBy', v_row."checked_in_by", 'createdAt', v_row."created_at") || jsonb_build_object('pass', jsonb_build_object('id', v_pass."id", 'organizationId', v_pass."tenant_id"::text, 'kind', v_pass."kind", 'holderUserId', v_pass."holder_user_id", 'holderName', v_pass."holder_name", 'holderEmail', v_pass."holder_email", 'subjectType', v_pass."subject_type", 'subjectId', v_pass."subject_id", 'bookingId', v_pass."booking_id", 'resourceId', v_pass."resource_id", 'usesAllowed', v_pass."uses_allowed", 'uses', v_pass."uses", 'validFrom', v_pass."valid_from", 'validUntil', v_pass."valid_until", 'status', v_pass."status", 'issuedBy', v_pass."issued_by", 'createdAt', v_pass."created_at", 'updatedAt', v_pass."updated_at", 'revokedAt', v_pass."revoked_at"));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.check_workflow_alerts (
  batch integer DEFAULT 100
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_pair record;
  v_alert "better_supabase"."workflow_alerts"%rowtype;
  v_run "better_supabase"."workflow_runs"%rowtype;
  v_fired integer := 0;
begin
  for v_pair in
    select x."id" as alert, y."id" as run from "better_supabase"."workflow_alerts" x
    join "better_supabase"."workflow_runs" y on y."attributes" ->> 'bsb.definition' = x."definition_id"::text
    where x."on_event" = 'slow'
      and y."mode" = 'live'
      and y."status" in ('queued', 'running', 'waiting')
      and y."created_at" < now() - x."threshold"
      and not exists (select 1 from "better_supabase"."workflow_alert_fires" z where z."alert_id" = x."id" and z."run_id" = y."id")
    limit greatest(coalesce(batch, 100), 1)
  loop
    select * into v_alert from "better_supabase"."workflow_alerts" x where x."id" = v_pair.alert;
    select * into v_run from "better_supabase"."workflow_runs" x where x."id" = v_pair.run;
    insert into "better_supabase"."workflow_alert_fires" ("alert_id", "run_id") values (v_alert."id", v_run."id")
      on conflict do nothing;
      if found then
        v_fired := v_fired + 1;
        perform "better_supabase".emit_event('workflow_alert.triggered', jsonb_build_object('alertId', v_alert."id", 'organizationId', v_run."tenant_id"::text, 'definition', v_alert."definition_id", 'onEvent', v_alert."on_event", 'channel', v_alert."channel", 'runId', v_run."id", 'status', v_run."status", 'error', v_run."error"), 'workflow-runs/' || v_run."id", (v_run."tenant_id")::text, 'workflow_alert.triggered:' || v_alert."id" || ':' || v_run."id", 'better-supabase/workflow-editor');
      end if;
  end loop;
  return v_fired;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.complete_engagement (
  engagement uuid,
  done       boolean,
  outcome    text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid := complete_engagement.engagement;
  v_tenant uuid;
  v_type text;
  v_subjects jsonb := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = complete_engagement.engagement), '[]'::jsonb);
  v_first jsonb := v_subjects -> 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "better_supabase"."engagements" x set
    "done_at" = case when complete_engagement.done then coalesce(x."done_at", now()) end,
    "outcome" = coalesce(complete_engagement.outcome, x."outcome"),
    "updated_at" = now()
  where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'engagements.manage'), false))
  returning x."tenant_id", x."type" into v_tenant, v_type;
  if v_tenant is null then
    raise exception 'no such engagement you can edit' using errcode = 'P0002', hint = 'ENGAGEMENT_NOT_FOUND';
  end if;
  if complete_engagement.done then
    perform "better_supabase".emit_event('engagement.completed', jsonb_build_object('organizationId', v_tenant, 'engagementId', v_id, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects), 'engagements/' || v_id::text, (v_tenant::text)::text, null, 'better-supabase/activities');
  end if;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."engagements" x where x."id" = v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_work_item (
  tenant    uuid,
  attrs     jsonb,
  assignees uuid[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_seq bigint;
  v_identifier text;
  v_id uuid;
  v_row "better_supabase"."work_items";
  v_linked integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', create_work_item.tenant, 'work_items.write'), false)) then
    raise exception 'not allowed to change work items' using errcode = '42501', hint = 'WORK_ITEM_FORBIDDEN';
  end if;
  if nullif(trim(create_work_item.attrs ->> 'title'), '') is null then
    raise exception 'a title is required' using errcode = '23502', hint = 'WORK_ITEM_TITLE_REQUIRED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_work_item_create"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using create_work_item.tenant, create_work_item.attrs;
    end if;
  end;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(create_work_item.tenant::text || ':work_item', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from "better_supabase"."work_items" x where x."tenant_id" = create_work_item.tenant;
  v_identifier := 'TASK-' || v_seq::text;
  begin
    insert into "better_supabase"."work_items" ("tenant_id", "number", "identifier", "title", "body", "parent_id", "team_id", "project_id", "iteration_id",
      "priority", "estimate", "progress", "start_at", "end_at", "due_at", "pipeline_id", "stage_id", "created_by")
    values (create_work_item.tenant, v_seq, v_identifier, trim(create_work_item.attrs ->> 'title'), create_work_item.attrs ->> 'body',
      (create_work_item.attrs ->> 'parentId')::uuid, (create_work_item.attrs ->> 'teamId')::uuid, (create_work_item.attrs ->> 'projectId')::uuid,
      (create_work_item.attrs ->> 'iterationId')::uuid, coalesce((create_work_item.attrs ->> 'priority')::smallint, 0),
      (create_work_item.attrs ->> 'estimate')::numeric, (create_work_item.attrs ->> 'progress')::smallint,
      (create_work_item.attrs ->> 'startAt')::timestamptz, (create_work_item.attrs ->> 'endAt')::timestamptz, (create_work_item.attrs ->> 'dueAt')::timestamptz,
      (create_work_item.attrs ->> 'pipelineId')::uuid, (create_work_item.attrs ->> 'stageId')::uuid, auth.uid())
    returning "id" into v_id;
  exception when check_violation or invalid_text_representation or datetime_field_overflow or numeric_value_out_of_range or foreign_key_violation then
    raise exception 'a work item field has an invalid value' using errcode = '22023', hint = 'WORK_ITEM_ATTRS_INVALID';
  end;
  if cardinality(coalesce(create_work_item.assignees, '{}')) > 0 then
    perform "better_supabase"."set_work_item_assignees"(v_id, create_work_item.assignees);
  end if;
  select * into v_row from "better_supabase"."work_items" x where x."id" = v_id;
  if jsonb_typeof(coalesce((create_work_item.attrs -> 'attachments'), '[]'::jsonb)) <> 'array' then
      raise exception 'attachments must be a list of attachment ids' using errcode = '22023', hint = 'WORK_ITEM_ATTACHMENTS_INVALID';
    end if;
    if jsonb_array_length(coalesce((create_work_item.attrs -> 'attachments'), '[]'::jsonb)) > 0 then
      update "better_supabase"."attachments" f set "subject_type" = 'work_item', "subject_id" = v_row."id"::text
      where f."id" = any (array(select jsonb_array_elements_text((create_work_item.attrs -> 'attachments'))::uuid))
        and f."organization_id" = v_row."tenant_id"
        and (f."subject_type" is null or (f."subject_type" = 'work_item' and f."subject_id" = v_row."id"::text))
        and ((auth.role() = 'service_role') or f."uploaded_by" = auth.uid());
      get diagnostics v_linked = row_count;
      if v_linked <> (select count(distinct x) from jsonb_array_elements_text((create_work_item.attrs -> 'attachments')) x) then
        raise exception 'attach only your own files in this organization that aren''t on another subject' using errcode = '22023', hint = 'WORK_ITEM_ATTACHMENTS_INVALID';
      end if;
    end if;
  perform "better_supabase".emit_event('work_item.created', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title"), 'work-items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_work_item_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) from "better_supabase"."work_items" x where x."id" = v_id);
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
    ('user', 'better_supabase.guests', '"better_supabase"."guests"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.drive_nodes', '"better_supabase"."drive_nodes"', 'created_by', true, '{}'::text[], true),
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
    ('user', 'better_supabase.ai_projects', '"better_supabase"."ai_projects"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_chats', '"better_supabase"."ai_chats"', 'owner_id', true, array['search_tsv']::text[], true),
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
    ('user', 'better_supabase.share_links', '"better_supabase"."share_links"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.reminders', '"better_supabase"."reminders"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.import_runs', '"better_supabase"."import_runs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.saved_view_preferences', '"better_supabase"."saved_view_preferences"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.bulk_runs', '"better_supabase"."bulk_runs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.calendar_events', '"better_supabase"."calendar_events"', 'created_by', false, '{}'::text[], true),
    ('user', 'better_supabase.calendar_attendees', '"better_supabase"."calendar_attendees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.calendar_working_hours', '"better_supabase"."calendar_working_hours"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.bookings', '"better_supabase"."bookings"', 'customer_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.versions', '"better_supabase"."versions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.trash_items', '"better_supabase"."trash_items"', 'trashed_by', true, '{}'::text[], true),
    ('user', 'better_supabase.reactions', '"better_supabase"."reactions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.custom_emoji', '"better_supabase"."custom_emoji"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.approval_requests', '"better_supabase"."approval_requests"', 'requested_by', true, '{}'::text[], true),
    ('user', 'better_supabase.approval_decisions', '"better_supabase"."approval_decisions"', 'approver', true, '{}'::text[], true),
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
    ('user', 'better_supabase.deals', '"better_supabase"."deals"', 'owner_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.deal_members', '"better_supabase"."deal_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.work_items', '"better_supabase"."work_items"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.work_item_checklist_items', '"better_supabase"."work_item_checklist_items"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.work_item_assignees', '"better_supabase"."work_item_assignees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.application_scorecards', '"better_supabase"."application_scorecards"', 'reviewer_user_id', true, '{}'::text[], true),
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
    ('user', 'better_supabase.maintenance_requests', '"better_supabase"."maintenance_requests"', 'reported_by', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.guests', '"better_supabase"."guests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.guest_grants', '"better_supabase"."guest_grants"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_nodes', '"better_supabase"."drive_nodes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_grants', '"better_supabase"."drive_grants"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.ai_projects', '"better_supabase"."ai_projects"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_chats', '"better_supabase"."ai_chats"', 'organization_id', true, array['search_tsv']::text[], true),
    ('organization', 'better_supabase.ai_tool_policies', '"better_supabase"."ai_tool_policies"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_moderation_events', '"better_supabase"."ai_moderation_events"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_sandboxes', '"better_supabase"."ai_sandboxes"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_files', '"better_supabase"."ai_files"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_documents', '"better_supabase"."ai_documents"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.knowledge_documents', '"better_supabase"."knowledge_documents"', 'organization_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.teams', '"better_supabase"."teams"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.team_members', '"better_supabase"."team_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.tags', '"better_supabase"."tags"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.taggings', '"better_supabase"."taggings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.status_history', '"better_supabase"."status_history"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.status_stages', '"better_supabase"."status_stages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.subject_lifecycles', '"better_supabase"."subject_lifecycles"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.field_definitions', '"better_supabase"."field_definitions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.field_values', '"better_supabase"."field_values"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.share_links', '"better_supabase"."share_links"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.recurrence_rules', '"better_supabase"."recurrence_rules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.reminders', '"better_supabase"."reminders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.import_runs', '"better_supabase"."import_runs"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.search_documents', '"better_supabase"."search_documents"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.metric_points', '"better_supabase"."metric_points"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.calendars', '"better_supabase"."calendars"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.calendar_events', '"better_supabase"."calendar_events"', 'tenant_id', false, '{}'::text[], true),
    ('organization', 'better_supabase.calendar_attendees', '"better_supabase"."calendar_attendees"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.deals', '"better_supabase"."deals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deal_contacts', '"better_supabase"."deal_contacts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deal_members', '"better_supabase"."deal_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deal_lines', '"better_supabase"."deal_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_items', '"better_supabase"."work_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_item_checklist_items', '"better_supabase"."work_item_checklist_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_item_assignees', '"better_supabase"."work_item_assignees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_projects', '"better_supabase"."work_projects"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.iterations', '"better_supabase"."iterations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.job_openings', '"better_supabase"."job_openings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.applications', '"better_supabase"."applications"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.application_scorecards', '"better_supabase"."application_scorecards"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.interviews', '"better_supabase"."interviews"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.invoices', '"better_supabase"."invoices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_lines', '"better_supabase"."invoice_lines"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.maintenance_requests', '"better_supabase"."maintenance_requests"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.posts', '"better_supabase"."posts"', 'tenant_id', true, '{}'::text[], true)
  ) as t(subject, name, tbl, col, purge, omit, exported)
  ) as t(subject, name, tbl, col, purge, omit, exported)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_ai_provider_key (
  id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."ai_provider_keys"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."ai_provider_keys" x where x."id" = delete_ai_provider_key.id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai.admin'), false)) then
    return null;
  end if;
  delete from "better_supabase"."ai_provider_keys" x where x."id" = v_row."id";
  perform "better_supabase".emit_event('ai_provider_key.deleted', jsonb_build_object('organizationId', v_row."organization_id"::text, 'keyId', v_row."id", 'provider', v_row."provider", 'name', v_row."name"), 'organizations/' || v_row."organization_id"::text || '/ai-provider-keys/' || v_row."id"::text, (v_row."organization_id")::text, null, 'better-supabase/ai-keys');
  perform better_supabase.audit_event(
    event_type => 'ai_provider_key.deleted',
    category => 'security',
    target_type => 'ai_provider_key',
    record_id => v_row."id"::text,
    target_label => v_row."provider" || '/' || v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'keyId', v_row."id", 'provider', v_row."provider", 'name', v_row."name")
  );
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'provider', v_row."provider", 'name', v_row."name", 'credential_ref', v_row."credential_ref", 'settings', v_row."settings", 'enabled', v_row."enabled", 'created_by', v_row."created_by", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_collection (
  collection uuid
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
  select x."tenant_id" into v_tenant from "better_supabase"."product_collections" x where x."id" = delete_collection.collection;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  delete from "better_supabase"."product_collections" x where x."id" = delete_collection.collection;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_engagement (
  engagement uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid := delete_engagement.engagement;
  v_tenant uuid;
  v_type text;
  v_subjects jsonb := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = delete_engagement.engagement), '[]'::jsonb);
  v_first jsonb := v_subjects -> 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from "better_supabase"."engagements" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'engagements.manage'), false))
  returning x."tenant_id", x."type" into v_tenant, v_type;
  if v_tenant is null then
    return false;
  end if;
  perform "better_supabase".emit_event('engagement.deleted', jsonb_build_object('organizationId', v_tenant, 'engagementId', v_id, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects), 'engagements/' || v_id::text, (v_tenant::text)::text, null, 'better-supabase/activities');
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_flag (
  key text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('flags.manage'), false))) then
    raise exception 'Not allowed to manage feature flags' using errcode = '42501', hint = 'FLAGS_FORBIDDEN';
  end if;
  delete from "better_supabase"."flags" x where x."key" = delete_flag.key;
  if not found then
    return false;
  end if;
  perform "better_supabase".emit_event('flag.deleted', jsonb_build_object('key', delete_flag.key), 'flags/' || delete_flag.key, null, null, 'better-supabase/feature-flags');
  perform better_supabase.audit_event(
    event_type => 'flag.deleted',
    category => 'configuration',
    target_type => 'flag',
    record_id => delete_flag.key,
    metadata => jsonb_build_object('key', delete_flag.key)
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_work_item (
  work_item uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."work_items";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from "better_supabase"."work_items" x
  where x."id" = delete_work_item.work_item
    and ((auth.role() = 'service_role') or x."created_by" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'work_items.manage'), false))
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  perform "better_supabase".emit_event('work_item.deleted', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title"), 'work-items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_work_item_checklist_item (
  checklist_item uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."work_items";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x.* into v_row from "better_supabase"."work_items" x join "better_supabase"."work_item_checklist_items" y on y."work_item_id" = x."id"
  where y."id" = delete_work_item_checklist_item.checklist_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'work_items.write'), false)) and x."archived_at" is null;
  if v_row."id" is null then
    return false;
  end if;
  delete from "better_supabase"."work_item_checklist_items" y where y."id" = delete_work_item_checklist_item.checklist_item;
  perform "better_supabase".emit_event('work_item.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'fields', jsonb_build_array('checklist')), 'work-items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.disable_service_principal (
  principal  uuid,
  created_by uuid DEFAULT NULL::uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."service_principals";
begin
  select * into v_row from "better_supabase"."service_principals" p where p."id" = disable_service_principal.principal and p."disabled_at" is null for update;
  if not found then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Service principals are managed by the service' using errcode = '42501', hint = 'SERVICE_PRINCIPAL_FORBIDDEN';
  end if;
  if disable_service_principal.created_by is not null and not (
    coalesce(better_supabase.member_can(disable_service_principal.created_by, v_row."tenant_id", 'service_principals.manage'), false)
    and coalesce(better_supabase.can_assign_as(disable_service_principal.created_by, v_row."tenant_id", v_row."role"), false)
  ) then
    raise exception 'You may not manage service principals with this role' using errcode = '42501', hint = 'SERVICE_PRINCIPAL_FORBIDDEN';
  end if;
  update "better_supabase"."service_principals" set "disabled_at" = now(), "is_default" = false where "id" = v_row."id";
  perform "better_supabase".emit_event('service_principal.disabled', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id"), 'service-principals/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/service-accounts');
  perform better_supabase.audit_event(
    event_type => 'service_principal.disabled',
    category => 'access',
    target_type => 'service_principal',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id"),
    actor_id => coalesce(disable_service_principal.created_by, auth.uid())
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.employee_from_application (
  application uuid,
  attrs       jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_application "better_supabase"."applications";
  v_job "better_supabase"."job_openings";
  v_existing "better_supabase"."employees";
begin
  select * into v_application from "better_supabase"."applications" x where x."id" = employee_from_application.application;
  if v_application."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_application."tenant_id", 'employees.write'), false)) then
    raise exception 'no such application you can turn into an employee' using errcode = 'P0002', hint = 'EMPLOYEE_ORIGIN_NOT_FOUND';
  end if;
  select * into v_existing from "better_supabase"."employees" x
  where x."tenant_id" = v_application."tenant_id" and x."origin_type" = 'application' and x."origin_id" = v_application."id"::text;
  if v_existing."id" is not null then
    return to_jsonb(v_existing);
  end if;
  if v_application."state" <> 'hired' then
    raise exception 'only a hired application becomes an employee' using errcode = '55000', hint = 'EMPLOYEE_APPLICATION_NOT_HIRED';
  end if;
  select * into v_job from "better_supabase"."job_openings" x where x."id" = v_application."job_id";
  return "better_supabase"."create_employee"(v_application."tenant_id", jsonb_strip_nulls(jsonb_build_object(
      'name', (case v_application."candidate_type"
      when 'message' then (select s."body"::text from "better_supabase"."messages" s where s."id" = (v_application."candidate_id")::uuid)
      when 'conversation' then (select s."title"::text from "better_supabase"."conversations" s where s."id" = (v_application."candidate_id")::uuid)
      when 'channel' then (select s."name"::text from "better_supabase"."channels" s where s."id" = (v_application."candidate_id")::uuid)
      when 'company' then (select s."name"::text from "better_supabase"."companies" s where s."id" = (v_application."candidate_id")::uuid)
      when 'person' then (select s."name"::text from "better_supabase"."people" s where s."id" = (v_application."candidate_id")::uuid)
      when 'deal' then (select s."name"::text from "better_supabase"."deals" s where s."id" = (v_application."candidate_id")::uuid)
      when 'course' then (select s."title"::text from "better_supabase"."courses" s where s."id" = (v_application."candidate_id")::uuid)
      when 'post' then (select s."title"::text from "better_supabase"."posts" s where s."id" = (v_application."candidate_id")::uuid)
      when 'engagement' then (select s."title"::text from "better_supabase"."engagements" s where s."id" = (v_application."candidate_id")::uuid)
      when 'work_item' then (select s."title"::text from "better_supabase"."work_items" s where s."id" = (v_application."candidate_id")::uuid)
      when 'employee' then (select s."name"::text from "better_supabase"."employees" s where s."id" = (v_application."candidate_id")::uuid)
      when 'ledger_account' then (select s."name"::text from "better_supabase"."ledger_accounts" s where s."id" = (v_application."candidate_id")::uuid)
      when 'product' then (select s."title"::text from "better_supabase"."products" s where s."id" = (v_application."candidate_id")::uuid)
      when 'product_variant' then (select s."sku"::text from "better_supabase"."product_variants" s where s."id" = (v_application."candidate_id")::uuid)
      when 'calendar_event' then (select s."title"::text from "better_supabase"."calendar_events" s where s."id" = (v_application."candidate_id")::uuid)
      when 'asset' then (select s."name"::text from "better_supabase"."assets" s where s."id" = (v_application."candidate_id")::uuid)
      when 'asset_location' then (select s."name"::text from "better_supabase"."asset_locations" s where s."id" = (v_application."candidate_id")::uuid)
      when 'lease' then (select s."title"::text from "better_supabase"."lease_agreements" s where s."id" = (v_application."candidate_id")::uuid)
      when 'maintenance_request' then (select s."title"::text from "better_supabase"."maintenance_requests" s where s."id" = (v_application."candidate_id")::uuid)
      when 'expense_report' then (select s."title"::text from "better_supabase"."expense_reports" s where s."id" = (v_application."candidate_id")::uuid)
      when 'expense_line' then (select s."description"::text from "better_supabase"."expense_lines" s where s."id" = (v_application."candidate_id")::uuid)
      when 'donation_fund' then (select s."name"::text from "better_supabase"."donation_funds" s where s."id" = (v_application."candidate_id")::uuid)
      when 'work_order' then (select s."title"::text from "better_supabase"."work_orders" s where s."id" = (v_application."candidate_id")::uuid)
      when 'shipment' then (select s."reference"::text from "better_supabase"."shipments" s where s."id" = (v_application."candidate_id")::uuid)
      when 'contract' then (select s."title"::text from "better_supabase"."contracts" s where s."id" = (v_application."candidate_id")::uuid)
      when 'control' then (select s."title"::text from "better_supabase"."controls" s where s."id" = (v_application."candidate_id")::uuid)
      when 'policy' then (select s."title"::text from "better_supabase"."policies" s where s."id" = (v_application."candidate_id")::uuid)
      when 'incident' then (select s."title"::text from "better_supabase"."incidents" s where s."id" = (v_application."candidate_id")::uuid)
      when 'document' then (select s."name"::text from "better_supabase"."documents" s where s."id" = (v_application."candidate_id")::uuid)
      when 'customer' then (select s."name"::text from "public"."customers" s where s."id" = (v_application."candidate_id")::uuid)
      when 'drive_node' then (select s."name"::text from "better_supabase"."drive_nodes" s where s."id" = (v_application."candidate_id")::uuid)
      when 'project' then (select s."name"::text from "public"."projects" s where s."id" = (v_application."candidate_id")::uuid)
      when 'task' then (select s."title"::text from "public"."tasks" s where s."id" = (v_application."candidate_id")::uuid)
      else null::text
    end),
      'jobTitle', v_job."title",
      'teamId', v_job."team_id",
      'employmentType', case when v_job."employment_type" = any (array['employee', 'contractor', 'intern', 'temporary']::text[]) then v_job."employment_type" end,
      'status', 'preboarding'))
    || coalesce(employee_from_application.attrs, '{}'::jsonb)
    || jsonb_build_object('origin', jsonb_build_object('type', 'application', 'id', v_application."id"::text)));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.invite_member (
  tenant        uuid,
  invitee_email text,
  invitee_role  text,
  valid_for     interval DEFAULT '7 days'::interval,
  prefill       jsonb    DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
  token text := encode(extensions.gen_random_bytes(24), 'hex');
  created "better_supabase"."invitations";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if valid_for is null or valid_for <= interval '0' or valid_for > '30 days'::interval then
    raise exception 'An invitation is valid for at most %', '30 days' using errcode = '22023', hint = 'INVITATION_VALIDITY';
  end if;
  if tenant is null then
    raise exception 'Platform invitations need platform roles: blocks.permissions.model ''catalog'' with platform assignments, or blocks.invitations.options.platformRoles under ''provider''' using errcode = '0A000', hint = 'INVITATION_SCOPE_UNSUPPORTED';
  end if;
  if not service and not coalesce(better_supabase.member_can(auth.uid(), tenant, 'members.invite'), false) then
    raise exception 'Not allowed to invite members' using errcode = '42501', hint = 'INVITATION_FORBIDDEN';
  end if;
  if better_supabase.tenant_disabled(tenant) or not exists (select 1 from "public"."organizations" o where o."id" = tenant) then
    raise exception 'The organization is not active' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if not (invitee_role = any (array['owner', 'admin', 'member']::text[])) then
    raise exception 'Unknown role %', invitee_role using errcode = '23514', hint = 'INVITATION_ROLE_UNKNOWN';
  end if;
  if not service and not better_supabase.can_assign(tenant, (invitee_role)::text) then
    raise exception 'That role is above your own' using errcode = '42501', hint = 'INVITATION_ROLE_FORBIDDEN';
  end if;
  if exists (
    select 1 from "public"."memberships" m join auth.users u on u.id = m."user_id"
    where m."organization_id" = tenant and lower(u.email) = lower(btrim(invitee_email))
  ) then
    raise exception '% is already a member', invitee_email using errcode = '23505', hint = 'INVITATION_ALREADY_MEMBER';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_invitation_create"(uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text)', v_hook::oid::regproc)
        using tenant, invitee_email, invitee_role;
    end if;
  end;
  delete from "better_supabase"."invitations" i
  where i."organization_id" = tenant
    and lower(i."email") = lower(btrim(invitee_email))
    and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null;
  insert into "better_supabase"."invitations" ("organization_id", "email", "role", "token_hash", "invited_by", "expires_at")
  values (tenant, lower(btrim(invitee_email)), invitee_role, encode(extensions.digest(token, 'sha256'), 'hex'), auth.uid(), now() + valid_for)
  returning * into created;
  perform "better_supabase".emit_event('invitation.created', jsonb_build_object('invitationId', created."id", 'organizationId', tenant::text, 'email', created."email", 'role', created."role"), 'invitations/' || created."id"::text, (tenant)::text, null, 'better-supabase/invitations');
  perform better_supabase.audit_event(
    event_type => 'invitation.created',
    category => 'membership',
    target_type => 'invitation',
    record_id => created."id"::text,
    tenant => (tenant)::uuid,
    metadata => jsonb_build_object('invitationId', created."id", 'organizationId', tenant::text, 'email', created."email", 'role', created."role")
  );
  return (jsonb_build_object(
    'id', created."id",
    'tenant', created."organization_id",
    'email', created."email",
    'role', created."role",
    'expires_at', created."expires_at",
    'created_at', created."created_at",
    'invited_by', created."invited_by",
    'organization', (select jsonb_build_object('id', o."id", 'name', o."name")
      from "public"."organizations" o where o."id" = created."organization_id"),
    'prefill', '{}'::jsonb,
    'inviter', (select jsonb_build_object('id', pr."id", 'username', pr."username", 'fullName', pr."full_name", 'firstName', pr."first_name", 'lastName', pr."last_name", 'avatar', pr."avatar_url")
      from "better_supabase"."profiles" pr where pr."id" = created."invited_by"),
    'token', token
  ) || "better_supabase"."invitation_extra"(created."id"));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.issue_pass (
  tenant       uuid,
  kind         text                     DEFAULT 'ticket'::text,
  holder_user  uuid                     DEFAULT NULL::uuid,
  holder_name  text                     DEFAULT NULL::text,
  holder_email text                     DEFAULT NULL::text,
  subject_type text                     DEFAULT NULL::text,
  subject_id   text                     DEFAULT NULL::text,
  booking_id   uuid                     DEFAULT NULL::uuid,
  resource_id  uuid                     DEFAULT NULL::uuid,
  uses_allowed integer                  DEFAULT NULL::integer,
  valid_from   timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  valid_until  timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."passes"%rowtype;
  v_resource uuid := issue_pass.resource_id;
  v_until timestamptz := issue_pass.valid_until;
  v_booking "better_supabase"."bookings"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', issue_pass.tenant, 'passes.manage'), false)) then
    raise exception 'not allowed to issue passes' using errcode = '42501', hint = 'PASS_FORBIDDEN';
  end if;
  if (issue_pass.subject_type is null) <> (issue_pass.subject_id is null) then
    raise exception 'pass both subject_type and subject_id, or neither' using errcode = '22023', hint = 'PASS_SUBJECT_INVALID';
  end if;
  if issue_pass.subject_type is not null
    and (case issue_pass.subject_type
      when 'message' then (select s."tenant_id"::text from "better_supabase"."messages" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'conversation' then (select s."tenant_id"::text from "better_supabase"."conversations" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'channel' then (select s."tenant_id"::text from "better_supabase"."channels" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'company' then (select s."tenant_id"::text from "better_supabase"."companies" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'person' then (select s."tenant_id"::text from "better_supabase"."people" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'deal' then (select s."tenant_id"::text from "better_supabase"."deals" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'course' then (select s."tenant_id"::text from "better_supabase"."courses" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'post' then (select s."tenant_id"::text from "better_supabase"."posts" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'engagement' then (select s."tenant_id"::text from "better_supabase"."engagements" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'work_item' then (select s."tenant_id"::text from "better_supabase"."work_items" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'employee' then (select s."tenant_id"::text from "better_supabase"."employees" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'ledger_account' then (select s."tenant_id"::text from "better_supabase"."ledger_accounts" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'product' then (select s."tenant_id"::text from "better_supabase"."products" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'product_variant' then (select s."tenant_id"::text from "better_supabase"."product_variants" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'calendar_event' then (select s."tenant_id"::text from "better_supabase"."calendar_events" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'asset' then (select s."tenant_id"::text from "better_supabase"."assets" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'asset_location' then (select s."tenant_id"::text from "better_supabase"."asset_locations" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'lease' then (select s."tenant_id"::text from "better_supabase"."lease_agreements" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'maintenance_request' then (select s."tenant_id"::text from "better_supabase"."maintenance_requests" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'expense_report' then (select s."tenant_id"::text from "better_supabase"."expense_reports" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'expense_line' then (select s."tenant_id"::text from "better_supabase"."expense_lines" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'donation_fund' then (select s."tenant_id"::text from "better_supabase"."donation_funds" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'work_order' then (select s."tenant_id"::text from "better_supabase"."work_orders" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'shipment' then (select s."tenant_id"::text from "better_supabase"."shipments" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'contract' then (select s."tenant_id"::text from "better_supabase"."contracts" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'control' then (select s."tenant_id"::text from "better_supabase"."controls" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'policy' then (select s."tenant_id"::text from "better_supabase"."policies" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'incident' then (select s."tenant_id"::text from "better_supabase"."incidents" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'document' then (select s."tenant_id"::text from "better_supabase"."documents" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'customer' then (select s."organization_id"::text from "public"."customers" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'drive_node' then (select s."tenant_id"::text from "better_supabase"."drive_nodes" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'application' then (select s."tenant_id"::text from "better_supabase"."applications" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'project' then (select s."organization_id"::text from "public"."projects" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'task' then (select s."organization_id"::text from "public"."tasks" s where s."id" = (issue_pass.subject_id)::uuid)
      else null::text
    end) is distinct from issue_pass.tenant::text then
    raise exception 'the record does not exist in this organization' using errcode = 'P0002', hint = 'PASS_SUBJECT_NOT_FOUND';
  end if;
  if issue_pass.holder_user is not null and not exists (select 1 from auth.users u where u.id = issue_pass.holder_user) then
    raise exception 'the holder does not exist' using errcode = 'P0002', hint = 'PASS_HOLDER_NOT_FOUND';
  end if;
  if issue_pass.booking_id is not null then
    select * into v_booking from "better_supabase"."bookings" bk
      where bk."id" = issue_pass.booking_id and bk."tenant_id" = issue_pass.tenant;
    if not found then
      raise exception 'the booking does not exist in this organization' using errcode = 'P0002', hint = 'PASS_BOOKING_NOT_FOUND';
    end if;
    if v_booking."status" = 'cancelled' then
      raise exception 'the booking is cancelled' using errcode = '55000', hint = 'PASS_BOOKING_CANCELLED';
    end if;
    if issue_pass.resource_id is not null and issue_pass.resource_id <> v_booking."resource_id" then
      raise exception 'the booking is for another resource' using errcode = '22023', hint = 'PASS_RESOURCE_MISMATCH';
    end if;
    v_resource := v_booking."resource_id";
    v_until := coalesce(v_until, upper(v_booking."during"));
  elsif issue_pass.resource_id is not null then
    if not exists (
      select 1 from "better_supabase"."booking_resources" rs
      where rs."id" = issue_pass.resource_id and rs."tenant_id" = issue_pass.tenant
    ) then
      raise exception 'the resource does not exist in this organization' using errcode = 'P0002', hint = 'PASS_RESOURCE_NOT_FOUND';
    end if;
  end if;
  if v_until is not null and v_until <= coalesce(issue_pass.valid_from, now()) then
    raise exception 'valid_until must be after valid_from and in the future' using errcode = '22023', hint = 'PASS_VALIDITY_INVALID';
  end if;
  insert into "better_supabase"."passes" ("tenant_id", "kind", "holder_user_id", "holder_name", "holder_email", "subject_type", "subject_id", "booking_id", "resource_id", "uses_allowed", "valid_from", "valid_until", "nonce", "issued_by")
  values (issue_pass.tenant, coalesce(issue_pass.kind, 'ticket'), issue_pass.holder_user, issue_pass.holder_name, lower(btrim(issue_pass.holder_email)),
    issue_pass.subject_type, issue_pass.subject_id, issue_pass.booking_id, v_resource,
    case when issue_pass.booking_id is not null then coalesce(issue_pass.uses_allowed, 1) else issue_pass.uses_allowed end,
    coalesce(issue_pass.valid_from, now()), v_until, encode(extensions.gen_random_bytes(16), 'hex'), auth.uid())
  returning * into v_row;
  perform "better_supabase".emit_event('pass.issued', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'kind', v_row."kind", 'holderUserId', v_row."holder_user_id", 'bookingId', v_row."booking_id"), 'passes/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/admission-passes');
  perform better_supabase.audit_event(
    event_type => 'pass.issued',
    category => 'access',
    target_type => 'pass',
    record_id => v_row."id"::text,
    summary => 'issued pass ' || v_row."kind",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'kind', v_row."kind", 'holderUserId', v_row."holder_user_id", 'bookingId', v_row."booking_id")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id"::text, 'kind', v_row."kind", 'holderUserId', v_row."holder_user_id", 'holderName', v_row."holder_name", 'holderEmail', v_row."holder_email", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'bookingId', v_row."booking_id", 'resourceId', v_row."resource_id", 'usesAllowed', v_row."uses_allowed", 'uses', v_row."uses", 'validFrom', v_row."valid_from", 'validUntil', v_row."valid_until", 'status', v_row."status", 'issuedBy', v_row."issued_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'revokedAt', v_row."revoked_at") || jsonb_build_object('nonce', v_row."nonce");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.log_engagement (
  tenant   uuid,
  attrs    jsonb,
  subjects jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid;
  v_tenant uuid := log_engagement.tenant;
  v_type text := log_engagement.attrs ->> 'type';
  v_title text := nullif(trim(log_engagement.attrs ->> 'title'), '');
  v_owner uuid := coalesce(nullif(log_engagement.attrs ->> 'ownerId', '')::uuid, auth.uid());
  v_previous_owner uuid;
  v_item jsonb;
  v_subjects jsonb;
  v_first jsonb;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'engagements.write'), false)) then
    raise exception 'not allowed to log engagements' using errcode = '42501', hint = 'ENGAGEMENT_FORBIDDEN';
  end if;
  if v_type is null or not (v_type = any ('{call,email,meeting,note,task}'::text[])) then
    raise exception 'unknown engagement type' using errcode = '22023', hint = 'ENGAGEMENT_TYPE_INVALID';
  end if;
  if v_title is null then
    raise exception 'a title is required' using errcode = '23502', hint = 'ENGAGEMENT_TITLE_REQUIRED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_engagement_log"(uuid, jsonb, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb, $3::jsonb)', v_hook::oid::regproc)
        using log_engagement.tenant, log_engagement.attrs, log_engagement.subjects;
    end if;
  end;
  insert into "better_supabase"."engagements" ("tenant_id", "type", "title", "body", "outcome", "owner_user_id", "due_at", "done_at", "duration_seconds", "external_ref", "created_by")
  values (v_tenant, v_type, v_title, log_engagement.attrs ->> 'body', log_engagement.attrs ->> 'outcome', v_owner,
    (log_engagement.attrs ->> 'dueAt')::timestamptz, (log_engagement.attrs ->> 'doneAt')::timestamptz,
    (log_engagement.attrs ->> 'durationSeconds')::integer, log_engagement.attrs ->> 'externalRef', auth.uid())
  on conflict ("tenant_id", "external_ref") where "external_ref" is not null do update set
    "title" = excluded."title", "body" = excluded."body", "outcome" = excluded."outcome",
    "due_at" = excluded."due_at", "done_at" = excluded."done_at",
    "duration_seconds" = excluded."duration_seconds", "updated_at" = now()
  returning "id" into v_id;
  
  if jsonb_typeof(coalesce(log_engagement.subjects, '[]')) <> 'array' then
    raise exception 'subjects must be a list of { type, id }' using errcode = '22023', hint = 'ENGAGEMENT_SUBJECTS_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(log_engagement.subjects, '[]')) loop
    if not (case (v_item ->> 'type')
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'maintenance_request' then exists (select 1 from "better_supabase"."maintenance_requests" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      else false
    end and "better_supabase"."can_subject"((v_item ->> 'type'), (v_item ->> 'id'), 'read')) then
      raise exception 'a subject is unknown or not readable in this organization' using errcode = '42501', hint = 'ENGAGEMENT_SUBJECT_FORBIDDEN';
    end if;
  end loop;
  delete from "better_supabase"."engagement_subjects" x where x."engagement_id" = v_id;
  insert into "better_supabase"."engagement_subjects" ("tenant_id", "engagement_id", "subject_type", "subject_id", "position")
  select v_tenant, v_id, s.value ->> 'type', s.value ->> 'id', s.ordinality::integer
  from jsonb_array_elements(coalesce(log_engagement.subjects, '[]')) with ordinality s
  on conflict do nothing;
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  perform "better_supabase".emit_event('engagement.logged', jsonb_build_object('organizationId', v_tenant, 'engagementId', v_id, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects), 'engagements/' || v_id::text, (v_tenant::text)::text, null, 'better-supabase/activities');
  if v_owner is not null and v_owner is distinct from auth.uid() and v_owner is distinct from v_previous_owner then
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'engagement.assigned',
      'tenant', v_tenant,
      'actor', auth.uid(),
      'subject_type', v_first ->> 'type',
      'subject_id', v_first ->> 'id',
      'summary', v_title,
      'recipients', jsonb_build_array(v_owner),
      'watchers', false,
      'key', 'engagement.assigned:' || v_id::text || ':' || v_owner::text,
      'data', jsonb_build_object('engagementId', v_id)
    ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_engagement_log"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."engagements" x where x."id" = v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.merge_companies (
  keep uuid,
  drop uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_keep "better_supabase"."companies";
  v_drop "better_supabase"."companies";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_keep from "better_supabase"."companies" x where x."id" = merge_companies.keep for update;
  select * into v_drop from "better_supabase"."companies" x where x."id" = merge_companies.drop for update;
  if v_keep."id" is null or v_drop."id" is null then
    raise exception 'company not found' using errcode = 'P0002', hint = 'PARTY_NOT_FOUND';
  end if;
  if v_keep."tenant_id" <> v_drop."tenant_id" or v_keep."id" = v_drop."id" or v_drop."merged_into" is not null then
    raise exception 'merge two different, unmerged records of one organization' using errcode = '22023', hint = 'PARTY_MERGE_INVALID';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_keep."tenant_id", 'parties.manage'), false)) then
    raise exception 'not allowed to change companies and people' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  update "better_supabase"."companies" x set "domain" = null, "merged_into" = merge_companies.keep,
    "archived_at" = coalesce(x."archived_at", now()), "updated_at" = now()
  where x."id" = merge_companies.drop;
  update "better_supabase"."companies" x set "domain" = coalesce(x."domain", v_drop."domain"), "website" = coalesce(x."website", v_drop."website"), "vat_id" = coalesce(x."vat_id", v_drop."vat_id"), "owner_user_id" = coalesce(x."owner_user_id", v_drop."owner_user_id"), "updated_at" = now()
  where x."id" = merge_companies.keep;
  insert into "better_supabase"."company_people" ("tenant_id", "company_id", "person_id", "role", "is_primary")
  select l."tenant_id", merge_companies.keep, l."person_id", l."role", false
  from "better_supabase"."company_people" l where l."company_id" = merge_companies.drop
  on conflict do nothing;
  delete from "better_supabase"."company_people" l where l."company_id" = merge_companies.drop;
  perform better_supabase.merge_subject_refs('better_supabase.companies', merge_companies.keep::text, merge_companies.drop::text);
  perform "better_supabase".emit_event('company.merged', jsonb_build_object('organizationId', v_keep."tenant_id", 'companyId', merge_companies.keep, 'name', v_keep."name", 'mergedId', merge_companies.drop), 'companies/' || merge_companies.keep::text, (v_keep."tenant_id"::text)::text, null, 'better-supabase/contacts');
  perform better_supabase.audit_event(
    event_type => 'company.merged',
    category => 'data',
    target_type => 'company',
    record_id => merge_companies.keep::text,
    target_label => v_keep."name",
    summary => 'merged ' || v_drop."name" || ' into ' || v_keep."name",
    tenant => (v_keep."tenant_id"::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_keep."tenant_id", 'companyId', merge_companies.keep, 'name', v_keep."name", 'mergedId', merge_companies.drop)
  );
  return (select to_jsonb(x) from "better_supabase"."companies" x where x."id" = merge_companies.keep);
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
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_keep."tenant_id", 'parties.manage'), false)) then
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

CREATE OR REPLACE FUNCTION better_supabase.notify_overdue_evidence_tasks()
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_task "better_supabase"."evidence_tasks"%rowtype;
  v_owner uuid;
  v_claims text;
  v_count integer := 0;
begin
  for v_task in
    select * from "better_supabase"."evidence_tasks" x
    where (x."active" and x."due_on" < current_date) and x."notified_for" is distinct from x."due_on"
    for update skip locked
  loop
    select y."owner_id" into v_owner from "better_supabase"."controls" y where y."id" = v_task."control_id";
    perform "better_supabase".emit_event('evidence_task.missed', jsonb_build_object('organizationId', v_task."tenant_id", 'evidenceTaskId', v_task."id", 'controlId', v_task."control_id", 'assigneeId', v_task."assignee_id", 'dueOn', v_task."due_on"), 'evidence-tasks/' || v_task."id"::text, (v_task."tenant_id")::text, null, 'better-supabase/compliance');
  perform better_supabase.audit_event(
    event_type => 'evidence_task.missed',
    category => 'data',
    target_type => 'evidence_task',
    record_id => v_task."id"::text,
    summary => 'evidence task overdue: ' || v_task."title",
    tenant => (v_task."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_task."tenant_id", 'evidenceTaskId', v_task."id", 'controlId', v_task."control_id", 'assigneeId', v_task."assignee_id", 'dueOn', v_task."due_on")
  );
    if coalesce(v_task."assignee_id", v_owner) is not null then
      v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'evidence_task.missed',
        'tenant', v_task."tenant_id",
        'actor', null,
        'subject_type', 'control',
        'subject_id', v_task."control_id"::text,
        'summary', v_task."title",
        'recipients', to_jsonb(array[coalesce(v_task."assignee_id", v_owner)]),
        'key', 'evidence_task.missed:' || v_task."id"::text || ':' || v_task."due_on"::text,
        'data', jsonb_build_object('evidenceTaskId', v_task."id", 'dueOn', v_task."due_on")
      ));
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
    update "better_supabase"."evidence_tasks" x set "notified_for" = v_task."due_on" where x."id" = v_task."id";
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.publish_policy (
  policy_id uuid,
  content   jsonb,
  label     text  DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."policies"%rowtype;
  v_version jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."policies" x where x."id" = publish_policy.policy_id for update;
  if not found then
    raise exception 'policy not found' using errcode = 'P0002', hint = 'POLICY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'controls.manage'), false)) then
    raise exception 'not allowed to manage policies' using errcode = '42501', hint = 'POLICY_FORBIDDEN';
  end if;
  if v_row."archived_at" is not null then
    raise exception 'an archived policy can''t be published' using errcode = '55000', hint = 'POLICY_ARCHIVED';
  end if;
  if publish_policy.content is null or jsonb_typeof(publish_policy.content) <> 'object' then
    raise exception 'content must be an object' using errcode = '22023', hint = 'POLICY_INVALID';
  end if;
  v_version := "better_supabase"."version_insert"(
    v_row."tenant_id", 'policy', v_row."id"::text, publish_policy.content,
    null, coalesce(publish_policy.label, v_row."title"), 'manual', true, auth.uid()
  );
  update "better_supabase"."policies" x set "current_version_id" = (v_version ->> 'id')::uuid,
    "version_number" = (v_version ->> 'number')::integer, "published_at" = now(), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  perform "better_supabase".emit_event('policy.published', jsonb_build_object('organizationId', v_row."tenant_id", 'policyId', v_row."id", 'versionId', v_row."current_version_id", 'number', v_row."version_number"), 'policies/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/compliance');
  perform better_supabase.audit_event(
    event_type => 'policy.published',
    category => 'data',
    target_type => 'policy',
    record_id => v_row."id"::text,
    summary => 'published policy ' || v_row."title" || ' version ' || v_row."version_number"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'policyId', v_row."id", 'versionId', v_row."current_version_id", 'number', v_row."version_number")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'ownerId', v_row."owner_id", 'requiresAcknowledgement', v_row."requires_acknowledgement", 'versionId', v_row."current_version_id", 'versionNumber', v_row."version_number", 'publishedAt', v_row."published_at", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."policy_acknowledgements" ack where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."policy_acknowledgements" ack join "public"."memberships" am on am."organization_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."policy_id" = v_row."id" and ack."version_id" = v_row."current_version_id"), 'memberCount', (select count(*) from "public"."memberships" pm where pm."organization_id" = v_row."tenant_id"));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.publish_workflow_version (
  version  uuid,
  compiled jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."workflow_versions"%rowtype;
  v_tenant uuid;
  v_errors jsonb;
  v_permissions text[];
  v_missing text[];
  v_service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."workflow_versions" x where x."id" = version for update;
  if not found then
    raise exception 'No such workflow version' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."workflow_definitions" x where x."id" = v_row."definition_id";
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'workflow.publish'), false))) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
      or not coalesce((select z."restricted" from "better_supabase"."workflow_definitions" z where z."id" = v_row."definition_id"), false)
      or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'workflow.admin'), false))
      or exists (
        select 1 from "better_supabase"."workflow_definition_grants" gr
        where gr."definition_id" = v_row."definition_id"
          and gr."action" in ('edit')
          and ((gr."principal_kind" = 'user' and gr."principal_id" = (select auth.uid())::text)
        or (gr."principal_kind" = 'team' and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = gr."principal_id" and tm."user_id" = (select auth.uid())))
        or (gr."principal_kind" = 'role' and exists (select 1 from "public"."memberships" mr where mr."organization_id" = v_tenant and mr."user_id" = (select auth.uid()) and mr."role"::text = gr."principal_id")))
      ))) then
    raise exception 'You may not publish this workflow' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  if compiled is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role may store a compiled form' using errcode = '42501', hint = 'WORKFLOW_COMPILED_FORBIDDEN';
  end if;
  if v_row."status" = 'published' then
    if compiled is not null then
      update "better_supabase"."workflow_versions" x set "compiled" = compiled
      where x."id" = v_row."id"
      returning * into v_row;
    end if;
    return jsonb_build_object(
    'id', v_row."id",
    'definition', v_row."definition_id",
    'version', v_row."version",
    'status', v_row."status",
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'publishedAt', v_row."published_at",
    'publishedBy', v_row."published_by",
    'owner', v_row."owner_kind",
    'permissions', to_jsonb(v_row."permissions"),
    'graph', v_row."graph",
    'compiled', v_row."compiled",
    'inputSchema', v_row."input_schema"
  );
  end if;
  v_errors := "better_supabase"."validate_workflow_graph"(v_row."graph");
  if jsonb_array_length(v_errors) > 0 then
    raise exception '%', (select string_agg(value, '; ') from jsonb_array_elements_text(v_errors))
      using errcode = '22023', hint = 'WORKFLOW_GRAPH_INVALID';
  end if;
  v_permissions := "better_supabase"."workflow_graph_permissions"(v_row."graph");
  if not v_service then
    select array_agg(p order by p) into v_missing
    from unnest(v_permissions) p
    where not coalesce(better_supabase.can('tenant', v_tenant, p), false);
    if v_missing is not null then
      raise exception 'You may not publish a workflow whose steps need %', array_to_string(v_missing, ', ')
        using errcode = '42501', hint = 'WORKFLOW_PUBLISHER_FORBIDDEN',
          detail = jsonb_build_object('permissions', to_jsonb(v_missing))::text;
    end if;
  end if;
  update "better_supabase"."workflow_versions" x set "status" = 'archived'
  where x."definition_id" = v_row."definition_id" and x."status" = 'published';
  update "better_supabase"."workflow_versions" x set
    "status" = 'published',
    "compiled" = compiled,
    "published_at" = now(),
    "published_by" = case when v_service then null else (select auth.uid()) end,
    "owner_kind" = case when v_service then 'organization' else 'user' end,
    "permissions" = v_permissions
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('workflow.published', jsonb_build_object('organizationId', v_tenant::text, 'definitionId', v_row."definition_id", 'versionId', v_row."id", 'version', v_row."version"), 'workflows/' || v_row."definition_id"::text, (v_tenant)::text, 'workflow.published:' || v_row."id"::text, 'better-supabase/workflow-editor');
  perform better_supabase.audit_event(
    event_type => 'workflow.published',
    category => 'configuration',
    target_type => 'workflow_version',
    record_id => v_row."id"::text,
    tenant => (v_tenant)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant::text, 'definitionId', v_row."definition_id", 'versionId', v_row."id", 'version', v_row."version"),
    idempotency_key => 'workflow.published:' || v_row."id"::text
  );
  return jsonb_build_object(
    'id', v_row."id",
    'definition', v_row."definition_id",
    'version', v_row."version",
    'status', v_row."status",
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'publishedAt', v_row."published_at",
    'publishedBy', v_row."published_by",
    'owner', v_row."owner_kind",
    'permissions', to_jsonb(v_row."permissions"),
    'graph', v_row."graph",
    'compiled', v_row."compiled",
    'inputSchema', v_row."input_schema"
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_rule_evaluation (
  rule       uuid,
  subject_id text,
  matched    boolean,
  results    jsonb   DEFAULT '{}'::jsonb,
  mode       text    DEFAULT 'live'::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_rule "better_supabase"."rules";
  v_row "better_supabase"."rule_evaluations";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_rule from "better_supabase"."rules" x where x."id" = record_rule_evaluation.rule;
  if v_rule."id" is null then
    raise exception 'No rule has this id' using errcode = 'P0002', hint = 'RULE_NOT_FOUND';
  end if;
  if coalesce(record_rule_evaluation.mode, 'live') not in ('live', 'test') then
    raise exception 'mode is live or test' using errcode = '22023', hint = 'RULE_INVALID';
  end if;
  if coalesce(record_rule_evaluation.mode, 'live') = 'live' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role records live evaluations' using errcode = '42501', hint = 'RULE_FORBIDDEN';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_rule."organization_id", 'rules.edit'), false)) then
    raise exception 'Testing rules needs the edit permission' using errcode = '42501', hint = 'RULE_FORBIDDEN';
  end if;
  insert into "better_supabase"."rule_evaluations" ("organization_id", "rule_id", "version", "subject_type", "subject_id", "trigger", "matched", "results", "mode", "evaluated_by")
  values (v_rule."organization_id", v_rule."id", v_rule."version", v_rule."subject_type", record_rule_evaluation.subject_id, v_rule."trigger",
    coalesce(record_rule_evaluation.matched, false), coalesce(record_rule_evaluation.results, '{}'::jsonb), coalesce(record_rule_evaluation.mode, 'live'), auth.uid())
  returning * into v_row;
  if v_row."mode" = 'live' and v_row."matched" then
    perform "better_supabase".emit_event('rule.matched', jsonb_build_object('organizationId', v_rule."organization_id"::text, 'ruleId', v_rule."id"::text, 'version', v_rule."version", 'subjectType', v_rule."subject_type", 'subjectId', record_rule_evaluation.subject_id, 'trigger', v_rule."trigger"), 'rules/' || v_rule."id"::text, (v_rule."organization_id")::text, null, 'better-supabase/automations');
  end if;
  return jsonb_build_object('id', v_row."id"::text, 'organizationId', v_row."organization_id", 'ruleId', v_row."rule_id", 'version', v_row."version", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'trigger', v_row."trigger", 'matched', v_row."matched", 'results', v_row."results", 'mode', v_row."mode", 'evaluatedBy', v_row."evaluated_by", 'evaluatedAt', v_row."evaluated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.refund_pass_credit()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_entry "better_supabase"."pass_credit_entries"%rowtype;
begin
  if new."status" <> 'cancelled' or old."status" = 'cancelled'
    or new."cancel_reason" is not distinct from 'bs:moving'
    or now() > lower(new."during") - '12 hours'::interval then
    return null;
  end if;
  for v_entry in
    insert into "better_supabase"."pass_credit_entries" ("tenant_id", "pass_id", "booking_id", "delta", "reason", "created_by")
    select spent."tenant_id", spent."pass_id", spent."booking_id", 1, 'refund', auth.uid()
    from "better_supabase"."pass_credit_entries" spent
    where spent."booking_id" = new."id" and spent."reason" = 'booking'
    on conflict ("booking_id", "reason") do nothing
    returning *
  loop
    update "better_supabase"."passes" x set "uses" = greatest(x."uses" - 1, 0), "updated_at" = now()
    where x."id" = v_entry."pass_id";
    perform "better_supabase".emit_event('pass.credit_refunded', jsonb_build_object('organizationId', v_entry."tenant_id"::text, 'id', v_entry."pass_id", 'entryId', v_entry."id", 'bookingId', v_entry."booking_id"), 'passes/' || v_entry."pass_id"::text, (v_entry."tenant_id")::text, null, 'better-supabase/admission-passes');
  perform better_supabase.audit_event(
    event_type => 'pass.credit_refunded',
    category => 'access',
    target_type => 'pass',
    record_id => v_entry."pass_id"::text,
    summary => 'refunded a credit to pass',
    tenant => (v_entry."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_entry."tenant_id"::text, 'id', v_entry."pass_id", 'entryId', v_entry."id", 'bookingId', v_entry."booking_id")
  );
  end loop;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.register_service_principal (
  principal  uuid,
  tenant     uuid,
  name       text,
  role       text,
  is_default boolean DEFAULT false,
  created_by uuid    DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Service principals are managed by the service' using errcode = '42501', hint = 'SERVICE_PRINCIPAL_FORBIDDEN';
  end if;
  if register_service_principal.created_by is not null and not (
    coalesce(better_supabase.member_can(register_service_principal.created_by, register_service_principal.tenant, 'service_principals.manage'), false)
    and coalesce(better_supabase.can_assign_as(register_service_principal.created_by, register_service_principal.tenant, register_service_principal.role), false)
  ) then
    raise exception 'You may not manage service principals with this role' using errcode = '42501', hint = 'SERVICE_PRINCIPAL_FORBIDDEN';
  end if;
  if not exists (
    select 1 from auth.users u
    where u.id = register_service_principal.principal
      and coalesce((u.raw_app_meta_data ->> 'bsb_service_principal')::boolean, false)
      and u.banned_until > now() + interval '50 years'
  ) then
    raise exception 'The user is not a service principal: create it with createServiceAccounts().create' using errcode = '22023', hint = 'SERVICE_PRINCIPAL_USER';
  end if;
  if not (register_service_principal.role = any (array['owner', 'admin', 'member']::text[])) then
    raise exception 'Unknown role %', register_service_principal.role using errcode = '22023', hint = 'ORGANIZATION_ROLE_UNKNOWN';
  end if;
  if register_service_principal.is_default then
    update "better_supabase"."service_principals" set "is_default" = false
    where "tenant_id" = register_service_principal.tenant and "is_default";
  end if;
  insert into "better_supabase"."service_principals" ("id", "tenant_id", "name", "role", "is_default", "created_by")
  values (register_service_principal.principal, register_service_principal.tenant, register_service_principal.name,
    register_service_principal.role, coalesce(register_service_principal.is_default, false), register_service_principal.created_by);
  perform "better_supabase".emit_event('service_principal.created', jsonb_build_object('organizationId', register_service_principal.tenant::text, 'id', register_service_principal.principal, 'name', register_service_principal.name, 'role', register_service_principal.role), 'service-principals/' || register_service_principal.principal::text, (register_service_principal.tenant)::text, null, 'better-supabase/service-accounts');
  perform better_supabase.audit_event(
    event_type => 'service_principal.created',
    category => 'access',
    target_type => 'service_principal',
    record_id => register_service_principal.principal::text,
    target_label => register_service_principal.name,
    tenant => (register_service_principal.tenant)::uuid,
    metadata => jsonb_build_object('organizationId', register_service_principal.tenant::text, 'id', register_service_principal.principal, 'name', register_service_principal.name, 'role', register_service_principal.role),
    actor_id => coalesce(register_service_principal.created_by, auth.uid())
  );
  return jsonb_build_object('id', register_service_principal.principal, 'tenant', register_service_principal.tenant,
    'name', register_service_principal.name, 'role', register_service_principal.role,
    'isDefault', coalesce(register_service_principal.is_default, false));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.remove_company_person (
  company uuid,
  person  uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_role text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select l."tenant_id", l."role" into v_tenant, v_role from "better_supabase"."company_people" l
  where l."company_id" = remove_company_person.company and l."person_id" = remove_company_person.person;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'parties.write'), false)) then
    raise exception 'not allowed to change companies and people' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  delete from "better_supabase"."company_people" l where l."company_id" = remove_company_person.company and l."person_id" = remove_company_person.person;
  perform "better_supabase".emit_event('company.person_unlinked', jsonb_build_object('organizationId', v_tenant, 'companyId', remove_company_person.company, 'personId', remove_company_person.person, 'role', v_role), 'companies/' || remove_company_person.company::text, (v_tenant::text)::text, null, 'better-supabase/contacts');
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.remove_from_collection (
  collection uuid,
  product    uuid
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
  select x."tenant_id" into v_tenant from "better_supabase"."product_collections" x where x."id" = remove_from_collection.collection;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  delete from "better_supabase"."collection_products" x where x."collection_id" = remove_from_collection.collection and x."product_id" = remove_from_collection.product;
  return found;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.remove_rule (
  id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."rules";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."rules" x where x."id" = remove_rule.id;
  if v_row."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'rules.admin'), false)) then
    return false;
  end if;
  delete from "better_supabase"."rules" x where x."id" = v_row."id";
  perform "better_supabase".emit_event('rule.removed', jsonb_build_object('organizationId', v_row."organization_id"::text, 'ruleId', v_row."id"::text, 'name', v_row."name", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'version', v_row."version"), 'rules/' || v_row."id"::text, (v_row."organization_id")::text, null, 'better-supabase/automations');
  perform better_supabase.audit_event(
    event_type => 'rule.removed',
    category => 'configuration',
    target_type => 'rule',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'ruleId', v_row."id"::text, 'name', v_row."name", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'version', v_row."version"),
    actor_id => auth.uid()
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.revoke_pass (
  pass_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."passes"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."passes" x where x."id" = revoke_pass.pass_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'passes.manage'), false)) then
    raise exception 'pass not found' using errcode = 'P0002', hint = 'PASS_NOT_FOUND';
  end if;
  if v_row."status" <> 'revoked' then
    update "better_supabase"."passes" x set "status" = 'revoked', "revoked_at" = now(), "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
    perform "better_supabase".emit_event('pass.revoked', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id"), 'passes/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/admission-passes');
  perform better_supabase.audit_event(
    event_type => 'pass.revoked',
    category => 'access',
    target_type => 'pass',
    record_id => v_row."id"::text,
    summary => 'revoked pass ' || v_row."kind",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id"::text, 'kind', v_row."kind", 'holderUserId', v_row."holder_user_id", 'holderName', v_row."holder_name", 'holderEmail', v_row."holder_email", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'bookingId', v_row."booking_id", 'resourceId', v_row."resource_id", 'usesAllowed', v_row."uses_allowed", 'uses', v_row."uses", 'validFrom', v_row."valid_from", 'validUntil', v_row."valid_until", 'status', v_row."status", 'issuedBy', v_row."issued_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'revokedAt', v_row."revoked_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_ai_provider_key (
  tenant         uuid,
  provider       text,
  credential_ref jsonb,
  name           text    DEFAULT 'default'::text,
  settings       jsonb   DEFAULT '{}'::jsonb,
  enabled        boolean DEFAULT true
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_old jsonb;
  v_row "better_supabase"."ai_provider_keys"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_ai_provider_key.tenant, 'ai.admin'), false)) then
    raise exception 'you may not manage provider keys here' using errcode = '42501', hint = 'AI_PROVIDER_KEY_FORBIDDEN';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and save_ai_provider_key.credential_ref is not null and jsonb_typeof(save_ai_provider_key.credential_ref) <> 'null'
    and (jsonb_typeof(save_ai_provider_key.credential_ref -> 'tenant') is distinct from 'string' or (save_ai_provider_key.credential_ref ->> 'tenant') is distinct from (save_ai_provider_key.tenant)::text) then
    raise exception 'credential_ref must carry the tenant % that owns it', save_ai_provider_key.tenant
      using errcode = '42501', hint = 'CREDENTIAL_REF_FOREIGN';
  end if;
  select x."credential_ref" into v_old from "better_supabase"."ai_provider_keys" x
  where x."organization_id" = save_ai_provider_key.tenant and x."provider" = save_ai_provider_key.provider and x."name" = coalesce(save_ai_provider_key.name, 'default')
  for update;
  insert into "better_supabase"."ai_provider_keys" ("organization_id", "provider", "name", "credential_ref", "settings", "enabled", "created_by")
  values (save_ai_provider_key.tenant, save_ai_provider_key.provider, coalesce(save_ai_provider_key.name, 'default'), save_ai_provider_key.credential_ref, coalesce(save_ai_provider_key.settings, '{}'), coalesce(save_ai_provider_key.enabled, true), auth.uid())
  on conflict ("organization_id", "provider", "name") do update set
    "credential_ref" = excluded."credential_ref",
    "settings" = excluded."settings",
    "enabled" = excluded."enabled",
    "updated_at" = now()
  returning * into v_row;
  perform "better_supabase".emit_event('ai_provider_key.saved', jsonb_build_object('organizationId', v_row."organization_id"::text, 'keyId', v_row."id", 'provider', v_row."provider", 'name', v_row."name"), 'organizations/' || v_row."organization_id"::text || '/ai-provider-keys/' || v_row."id"::text, (v_row."organization_id")::text, null, 'better-supabase/ai-keys');
  perform better_supabase.audit_event(
    event_type => 'ai_provider_key.saved',
    category => 'security',
    target_type => 'ai_provider_key',
    record_id => v_row."id"::text,
    target_label => v_row."provider" || '/' || v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'keyId', v_row."id", 'provider', v_row."provider", 'name', v_row."name")
  );
  return jsonb_build_object('key', jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'provider', v_row."provider", 'name', v_row."name", 'credential_ref', v_row."credential_ref", 'settings', v_row."settings", 'enabled', v_row."enabled", 'created_by', v_row."created_by", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at"), 'replaced', v_old);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_collection (
  tenant     uuid,
  collection uuid,
  title      text,
  slug       text,
  kind       text,
  rule       jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid := save_collection.collection;
  v_kind text := coalesce(save_collection.kind, 'manual');
  v_slug text := coalesce(nullif(save_collection.slug, ''), trim(both '-' from regexp_replace(lower(save_collection.title), '[^a-z0-9]+', '-', 'g')));
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_collection.tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  if v_slug is null or v_slug !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' then
    raise exception 'the slug must be lower-case letters, digits and hyphens' using errcode = '22023', hint = 'CATALOG_SLUG_INVALID';
  end if;
  if v_kind not in ('manual', 'rule') then
    raise exception 'the kind must be manual or rule' using errcode = '22023', hint = 'CATALOG_COLLECTION_KIND';
  end if;
  if (v_kind = 'rule') <> (save_collection.rule is not null) then
    raise exception 'a rule collection needs a rule and a manual one none' using errcode = '22023', hint = 'CATALOG_COLLECTION_RULE';
  end if;
  if v_kind = 'rule' and not (
    jsonb_typeof(save_collection.rule) = 'object'
    and save_collection.rule ->> 'type' = 'group'
    and save_collection.rule ->> 'combinator' in ('and', 'or')
    and jsonb_typeof(save_collection.rule -> 'rules') = 'array'
  ) then
    raise exception 'the rule must be a filter group with a combinator and rules' using errcode = '22023', hint = 'CATALOG_COLLECTION_RULE';
  end if;
  begin
    if v_id is null then
      insert into "better_supabase"."product_collections" ("tenant_id", "title", "slug", "kind", "rule")
      values (save_collection.tenant, save_collection.title, v_slug, v_kind, save_collection.rule)
      returning "id" into v_id;
    else
      update "better_supabase"."product_collections" x set "title" = save_collection.title, "slug" = v_slug, "kind" = v_kind,
        "rule" = save_collection.rule, "updated_at" = now()
      where x."id" = v_id and x."tenant_id" = save_collection.tenant;
      if not found then
        raise exception 'collection not found' using errcode = 'P0002', hint = 'CATALOG_COLLECTION_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'another collection has this slug' using errcode = '23505', hint = 'CATALOG_SLUG_TAKEN';
  end;
  if v_kind = 'rule' then
    delete from "better_supabase"."collection_products" x where x."collection_id" = v_id;
  end if;
  return jsonb_build_object('id', v_id, 'slug', v_slug, 'kind', v_kind);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_company (
  tenant  uuid,
  company uuid,
  attrs   jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid := save_company.company;
  v_created boolean := save_company.company is null;
  v_row jsonb;
  v_owner uuid;
  v_previous_owner uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_company.tenant, 'parties.write'), false)) then
    raise exception 'not allowed to change companies and people' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  if jsonb_typeof(coalesce(save_company.attrs, '{}')) <> 'object' then
    raise exception 'attrs must be an object' using errcode = '22023', hint = 'PARTY_ATTRS_INVALID';
  end if;
  if save_company.attrs ? 'lifecycle' and not (save_company.attrs ->> 'lifecycle' = any ('{lead,prospect,customer,churned}'::text[])) then
    raise exception 'unknown lifecycle stage' using errcode = '22023', hint = 'PARTY_LIFECYCLE_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_company_save"(uuid, uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::jsonb)', v_hook::oid::regproc)
        using save_company.tenant, save_company.company, save_company.attrs;
    end if;
  end;
  begin
    if v_created then
      if nullif(trim(save_company.attrs ->> 'name'), '') is null then
        raise exception 'a name is required' using errcode = '23502', hint = 'PARTY_NAME_REQUIRED';
      end if;
      insert into "better_supabase"."companies" ("tenant_id", "name", "domain", "website", "vat_id", "lifecycle", "owner_user_id", "address", "created_by")
      values (save_company.tenant, nullif(trim(save_company.attrs ->> 'name'), ''), lower(nullif(trim(save_company.attrs ->> 'domain'), '')), nullif(trim(save_company.attrs ->> 'website'), ''), nullif(trim(save_company.attrs ->> 'vatId'), ''), coalesce(nullif(trim(save_company.attrs ->> 'lifecycle'), ''), ('{lead,prospect,customer,churned}'::text[])[1]), nullif(save_company.attrs ->> 'ownerId', '')::uuid, save_company.attrs -> 'address', auth.uid())
      returning "id", "owner_user_id" into v_id, v_owner;
    else
      select x."owner_user_id" into v_previous_owner from "better_supabase"."companies" x
      where x."id" = save_company.company and x."tenant_id" = save_company.tenant;
      update "better_supabase"."companies" x set "name" = case when save_company.attrs ? 'name' then coalesce(nullif(trim(save_company.attrs ->> 'name'), ''), x."name") else x."name" end,
        "domain" = case when save_company.attrs ? 'domain' then lower(nullif(trim(save_company.attrs ->> 'domain'), '')) else x."domain" end,
        "website" = case when save_company.attrs ? 'website' then nullif(trim(save_company.attrs ->> 'website'), '') else x."website" end,
        "vat_id" = case when save_company.attrs ? 'vatId' then nullif(trim(save_company.attrs ->> 'vatId'), '') else x."vat_id" end,
        "lifecycle" = case when save_company.attrs ? 'lifecycle' then coalesce(nullif(trim(save_company.attrs ->> 'lifecycle'), ''), x."lifecycle") else x."lifecycle" end,
        "owner_user_id" = case when save_company.attrs ? 'ownerId' then nullif(save_company.attrs ->> 'ownerId', '')::uuid else x."owner_user_id" end,
        "address" = case when save_company.attrs ? 'address' then save_company.attrs -> 'address' else x."address" end,
        "updated_at" = now()
      where x."id" = save_company.company and x."tenant_id" = save_company.tenant and x."merged_into" is null
      returning x."owner_user_id" into v_owner;
      if not found then
        raise exception 'company not found' using errcode = 'P0002', hint = 'PARTY_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'another company has this domain' using errcode = '23505', hint = 'PARTY_DOMAIN_TAKEN';
  end;
  select to_jsonb(x) into v_row from "better_supabase"."companies" x where x."id" = v_id;
  if v_created then
    perform "better_supabase".emit_event('company.created', jsonb_build_object('organizationId', save_company.tenant, 'companyId', v_id, 'name', v_row ->> 'name'), 'companies/' || v_id::text, (save_company.tenant::text)::text, null, 'better-supabase/contacts');
  else
    perform "better_supabase".emit_event('company.updated', jsonb_build_object('organizationId', save_company.tenant, 'companyId', v_id, 'name', v_row ->> 'name'), 'companies/' || v_id::text, (save_company.tenant::text)::text, null, 'better-supabase/contacts');
  end if;
  if v_owner is not null and v_owner is distinct from v_previous_owner then
    insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
    values (save_company.tenant, v_owner, 'company', v_id::text, 'participating')
    on conflict do nothing;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_company_save"(uuid, boolean)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::boolean)', v_hook::oid::regproc)
        using v_id, v_created;
    end if;
  end;
  return v_row;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_control (
  framework_id uuid,
  code         text,
  title        text,
  description  text    DEFAULT NULL::text,
  owner_id     uuid    DEFAULT NULL::uuid,
  applicable   boolean DEFAULT true,
  control_id   uuid    DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_framework "better_supabase"."control_frameworks"%rowtype;
  v_row "better_supabase"."controls"%rowtype;
  v_new boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_framework from "better_supabase"."control_frameworks" x where x."id" = save_control.framework_id;
  if not found then
    raise exception 'framework not found' using errcode = 'P0002', hint = 'CONTROL_FRAMEWORK_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_framework."tenant_id", 'controls.manage'), false)) then
    raise exception 'not allowed to manage controls' using errcode = '42501', hint = 'CONTROLS_FORBIDDEN';
  end if;
  if nullif(trim(save_control.code), '') is null or nullif(trim(save_control.title), '') is null then
    raise exception 'a control needs a code and a title' using errcode = '22023', hint = 'CONTROLS_INVALID';
  end if;
  if save_control.owner_id is not null and not exists (select 1 from "public"."memberships" m where m."organization_id" = v_framework."tenant_id" and m."user_id" = save_control.owner_id) then
    raise exception 'the owner must be a member of the organization' using errcode = '22023', hint = 'CONTROLS_INVALID';
  end if;
  if save_control.control_id is null then
    insert into "better_supabase"."controls" ("tenant_id", "framework_id", "code", "title", "description", "owner_id", "applicable")
    values (v_framework."tenant_id", v_framework."id", trim(save_control.code), trim(save_control.title), nullif(trim(save_control.description), ''), save_control.owner_id, coalesce(save_control.applicable, true))
    on conflict ("framework_id", "code") do update
      set "title" = excluded."title", "description" = excluded."description",
        "owner_id" = excluded."owner_id", "applicable" = excluded."applicable", "updated_at" = now()
    returning * into v_row;
  else
    update "better_supabase"."controls" x set "code" = trim(save_control.code), "title" = trim(save_control.title),
      "description" = nullif(trim(save_control.description), ''), "owner_id" = save_control.owner_id,
      "applicable" = coalesce(save_control.applicable, true), "updated_at" = now()
      where x."id" = save_control.control_id and x."framework_id" = v_framework."id"
      returning * into v_row;
    if not found then
      raise exception 'control not found' using errcode = 'P0002', hint = 'CONTROL_NOT_FOUND';
    end if;
  end if;
  perform "better_supabase".emit_event('control.saved', jsonb_build_object('organizationId', v_row."tenant_id", 'controlId', v_row."id", 'frameworkId', v_row."framework_id", 'code', v_row."code"), 'controls/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/compliance');
  perform better_supabase.audit_event(
    event_type => 'control.saved',
    category => 'data',
    target_type => 'control',
    record_id => v_row."id"::text,
    summary => 'saved control ' || v_row."code",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'controlId', v_row."id", 'frameworkId', v_row."framework_id", 'code', v_row."code")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'frameworkId', v_row."framework_id", 'code', v_row."code", 'title', v_row."title", 'description', v_row."description", 'ownerId', v_row."owner_id", 'applicable', v_row."applicable", 'status', case
    when not v_row."applicable" then 'not_applicable'
    when exists (select 1 from "better_supabase"."evidence_tasks" st where st."control_id" = v_row."id" and (st."active" and st."due_on" < current_date)) then 'failing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = v_row."id" and (se."valid_until" is null or se."valid_until" >= current_date)) then 'passing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = v_row."id") then 'failing'
    else 'not_started'
  end, 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_engagement_notes (
  engagement uuid,
  notes      jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_type text;
  v_summary text := nullif(trim(save_engagement_notes.notes ->> 'summary'), '');
  v_items jsonb := coalesce(save_engagement_notes.notes -> 'actionItems', '[]'::jsonb);
  v_subjects jsonb;
  v_first jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."type" into v_tenant, v_type
  from "better_supabase"."engagements" x where x."id" = save_engagement_notes.engagement and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'engagements.manage'), false));
  if v_tenant is null then
    raise exception 'no such engagement you can edit' using errcode = 'P0002', hint = 'ENGAGEMENT_NOT_FOUND';
  end if;
  if v_summary is null or length(v_summary) > 20000 then
    raise exception 'notes need a summary of at most 20000 characters' using errcode = '22023', hint = 'ENGAGEMENT_NOTES_INVALID';
  end if;
  if jsonb_typeof(v_items) <> 'array' or exists (
    select 1 from jsonb_array_elements(v_items) i
    where jsonb_typeof(i.value) <> 'object' or jsonb_typeof(i.value -> 'text') is distinct from 'string'
  ) then
    raise exception 'actionItems must be a list of { text }' using errcode = '22023', hint = 'ENGAGEMENT_NOTES_INVALID';
  end if;
  insert into "better_supabase"."engagement_notes" ("engagement_id", "tenant_id", "summary", "action_items", "model", "source", "created_by")
  values (save_engagement_notes.engagement, v_tenant, v_summary, v_items, nullif(save_engagement_notes.notes ->> 'model', ''),
    case when save_engagement_notes.notes ->> 'source' = 'member' then 'member' else 'ai' end, auth.uid())
  on conflict ("engagement_id") do update set
    "summary" = excluded."summary", "action_items" = excluded."action_items",
    "model" = excluded."model", "source" = excluded."source", "updated_at" = now();
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = save_engagement_notes.engagement), '[]'::jsonb);
  v_first := v_subjects -> 0;
  perform "better_supabase".emit_event('engagement.summarized', jsonb_build_object('organizationId', v_tenant, 'engagementId', save_engagement_notes.engagement, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects), 'engagements/' || save_engagement_notes.engagement::text, (v_tenant::text)::text, 'engagement.summarized:' || save_engagement_notes.engagement::text || ':' || md5(save_engagement_notes.notes::text), 'better-supabase/activities');
  return (select jsonb_build_object('engagementId', nx."engagement_id", 'organizationId', nx."tenant_id", 'summary', nx."summary", 'actionItems', nx."action_items", 'model', nx."model", 'source', nx."source", 'createdBy', nx."created_by", 'createdAt', nx."created_at", 'updatedAt', nx."updated_at") from "better_supabase"."engagement_notes" nx where nx."engagement_id" = save_engagement_notes.engagement);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_engagement_transcript (
  recording uuid,
  segments  jsonb,
  attrs     jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_recording uuid := save_engagement_transcript.recording;
  v_engagement uuid;
  v_tenant uuid;
  v_type text;
  v_item jsonb;
  v_position integer;
  v_subjects jsonb;
  v_first jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select rx."engagement_id", rx."tenant_id", x."type" into v_engagement, v_tenant, v_type
  from "better_supabase"."engagement_recordings" rx
  join "better_supabase"."engagements" x on x."id" = rx."engagement_id"
  where rx."id" = v_recording and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'engagements.manage'), false))
  for update of rx;
  if v_engagement is null then
    raise exception 'no such recording you can edit' using errcode = 'P0002', hint = 'ENGAGEMENT_RECORDING_NOT_FOUND';
  end if;
  if jsonb_typeof(save_engagement_transcript.segments) is distinct from 'array'
    or jsonb_array_length(save_engagement_transcript.segments) > 20000 then
    raise exception 'segments must be a list of at most 20000 { startMs, endMs, text }' using errcode = '22023', hint = 'ENGAGEMENT_TRANSCRIPT_INVALID';
  end if;
  for v_item, v_position in select value, ordinality from jsonb_array_elements(save_engagement_transcript.segments) with ordinality loop
    if jsonb_typeof(v_item) is distinct from 'object'
      or jsonb_typeof(v_item -> 'text') is distinct from 'string'
      or jsonb_typeof(v_item -> 'startMs') is distinct from 'number'
      or jsonb_typeof(v_item -> 'endMs') is distinct from 'number'
      or (v_item ->> 'startMs')::numeric < 0
      or (v_item ->> 'endMs')::numeric < (v_item ->> 'startMs')::numeric
      or jsonb_typeof(coalesce(v_item -> 'confidence', 'null')) not in ('number', 'null') then
      raise exception 'segment % needs startMs <= endMs and a text', v_position using errcode = '22023', hint = 'ENGAGEMENT_TRANSCRIPT_INVALID';
    end if;
  end loop;
  delete from "better_supabase"."engagement_transcript_segments" sx where sx."recording_id" = v_recording;
  insert into "better_supabase"."engagement_transcript_segments" ("recording_id", "tenant_id", "position", "speaker", "speaker_user_id", "starts_ms", "ends_ms", "text", "confidence")
  select v_recording, v_tenant, i.ordinality::integer, nullif(i.value ->> 'speaker', ''), nullif(i.value ->> 'speakerUserId', '')::uuid,
    round((i.value ->> 'startMs')::numeric)::integer, round((i.value ->> 'endMs')::numeric)::integer, i.value ->> 'text', (i.value ->> 'confidence')::real
  from jsonb_array_elements(save_engagement_transcript.segments) with ordinality i;
  update "better_supabase"."engagement_recordings" rx set
    "status" = 'transcribed',
    "error" = null,
    "language" = coalesce(nullif(save_engagement_transcript.attrs ->> 'language', ''), rx."language"),
    "duration_seconds" = coalesce((save_engagement_transcript.attrs ->> 'durationSeconds')::integer, rx."duration_seconds"),
    "model" = coalesce(nullif(save_engagement_transcript.attrs ->> 'model', ''), rx."model"),
    "transcribed_at" = now()
  where rx."id" = v_recording;
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = v_engagement), '[]'::jsonb);
  v_first := v_subjects -> 0;
  perform "better_supabase".emit_event('engagement.transcribed', jsonb_build_object('organizationId', v_tenant, 'engagementId', v_engagement, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects, 'recordingId', v_recording), 'engagements/' || v_engagement::text, (v_tenant::text)::text, 'engagement.transcribed:' || v_recording::text || ':' || md5(save_engagement_transcript.segments::text), 'better-supabase/activities');
  return (select jsonb_build_object('id', rx."id", 'organizationId', rx."tenant_id", 'engagementId', rx."engagement_id", 'fileId', rx."file_id", 'filename', rx."filename", 'mediaType', rx."media_type", 'status', rx."status", 'language', rx."language", 'durationSeconds', rx."duration_seconds", 'error', rx."error", 'model', rx."model", 'segmentCount', (select count(*)::integer from "better_supabase"."engagement_transcript_segments" sc where sc."recording_id" = rx."id"), 'createdBy', rx."created_by", 'createdAt', rx."created_at", 'transcribedAt', rx."transcribed_at") from "better_supabase"."engagement_recordings" rx where rx."id" = v_recording);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_flag (
  key        text,
  definition jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  d jsonb := coalesce(definition, '{}');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('flags.manage'), false))) then
    raise exception 'Not allowed to manage feature flags' using errcode = '42501', hint = 'FLAGS_FORBIDDEN';
  end if;
  insert into "better_supabase"."flags" as x ("key", "type", "description", "variants", "default_variant", "enabled", "archived", "rules", "rollout_percentage", "rollout_variant")
  values (
    save_flag.key,
    coalesce(d ->> 'type', 'boolean'),
    d ->> 'description',
    coalesce(d -> 'variants', '{"on": true, "off": false}'::jsonb),
    coalesce(d ->> 'default_variant', 'off'),
    coalesce((d ->> 'enabled')::boolean, true),
    coalesce((d ->> 'archived')::boolean, false),
    coalesce(d -> 'rules', '[]'::jsonb),
    coalesce((d ->> 'rollout_percentage')::numeric, 0),
    d ->> 'rollout_variant'
  )
  on conflict ("key") do update set
    "type" = case when d ? 'type' then excluded."type" else x."type" end,
    "description" = case when d ? 'description' then excluded."description" else x."description" end,
    "variants" = case when d ? 'variants' then excluded."variants" else x."variants" end,
    "default_variant" = case when d ? 'default_variant' then excluded."default_variant" else x."default_variant" end,
    "enabled" = case when d ? 'enabled' then excluded."enabled" else x."enabled" end,
    "archived" = case when d ? 'archived' then excluded."archived" else x."archived" end,
    "rules" = case when d ? 'rules' then excluded."rules" else x."rules" end,
    "rollout_percentage" = case when d ? 'rollout_percentage' then excluded."rollout_percentage" else x."rollout_percentage" end,
    "rollout_variant" = case when d ? 'rollout_variant' then excluded."rollout_variant" else x."rollout_variant" end,
    "updated_at" = now();
  perform "better_supabase".emit_event('flag.saved', jsonb_build_object('key', save_flag.key), 'flags/' || save_flag.key, null, null, 'better-supabase/feature-flags');
  perform better_supabase.audit_event(
    event_type => 'flag.saved',
    category => 'configuration',
    target_type => 'flag',
    record_id => save_flag.key,
    metadata => jsonb_build_object('key', save_flag.key)
  );
  return (select v from jsonb_array_elements("better_supabase"."flag_definitions"()) v where v ->> 'key' = save_flag.key);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_job (
  tenant uuid,
  job    uuid,
  attrs  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_job "better_supabase"."job_openings";
  v_was text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', save_job.tenant, 'hiring.manage'), false)) then
    raise exception 'not allowed to manage jobs' using errcode = '42501', hint = 'HIRING_FORBIDDEN';
  end if;
  if save_job.job is not null then
    select * into v_job from "better_supabase"."job_openings" x where x."id" = save_job.job and x."tenant_id" = save_job.tenant;
    if v_job."id" is null then
      raise exception 'job not found' using errcode = 'P0002', hint = 'HIRING_JOB_NOT_FOUND';
    end if;
    v_was := v_job."status";
  end if;
  begin
    if save_job.job is null then
      insert into "better_supabase"."job_openings" ("tenant_id", "title", "team_id", "location", "employment_type", "description", "hiring_manager_user_id", "status")
      values (save_job.tenant, save_job.attrs ->> 'title', (save_job.attrs ->> 'teamId')::uuid, save_job.attrs ->> 'location',
        save_job.attrs ->> 'employmentType', save_job.attrs ->> 'description', (save_job.attrs ->> 'hiringManagerId')::uuid,
        coalesce(save_job.attrs ->> 'status', 'draft'))
      returning * into v_job;
    else
      update "better_supabase"."job_openings" x set
        "title" = coalesce(save_job.attrs ->> 'title', x."title"),
        "team_id" = case when save_job.attrs ? 'teamId' then (save_job.attrs ->> 'teamId')::uuid else x."team_id" end,
        "location" = case when save_job.attrs ? 'location' then save_job.attrs ->> 'location' else x."location" end,
        "employment_type" = case when save_job.attrs ? 'employmentType' then save_job.attrs ->> 'employmentType' else x."employment_type" end,
        "description" = case when save_job.attrs ? 'description' then save_job.attrs ->> 'description' else x."description" end,
        "hiring_manager_user_id" = case when save_job.attrs ? 'hiringManagerId' then (save_job.attrs ->> 'hiringManagerId')::uuid else x."hiring_manager_user_id" end,
        "status" = coalesce(save_job.attrs ->> 'status', x."status"),
        "updated_at" = now()
      where x."id" = save_job.job
      returning * into v_job;
    end if;
  exception when check_violation or not_null_violation or invalid_text_representation then
    raise exception 'a job needs a title and a status of draft, open or closed' using errcode = '22023', hint = 'HIRING_JOB_INVALID';
  end;
  if v_job."status" is distinct from v_was then
    if v_job."status" = 'open' then
      update "better_supabase"."job_openings" x set "opened_at" = coalesce(x."opened_at", now()), "closed_at" = null where x."id" = v_job."id" returning * into v_job;
      perform "better_supabase".emit_event('job.opened', jsonb_build_object('organizationId', v_job."tenant_id", 'jobId', v_job."id", 'title', v_job."title"), 'jobs/' || v_job."id"::text, (v_job."tenant_id"::text)::text, null, 'better-supabase/hiring');
    elsif v_job."status" = 'closed' then
      update "better_supabase"."job_openings" x set "closed_at" = now() where x."id" = v_job."id" returning * into v_job;
      perform "better_supabase".emit_event('job.closed', jsonb_build_object('organizationId', v_job."tenant_id", 'jobId', v_job."id", 'title', v_job."title"), 'jobs/' || v_job."id"::text, (v_job."tenant_id"::text)::text, null, 'better-supabase/hiring');
    end if;
  end if;
  return to_jsonb(v_job);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_person (
  tenant uuid,
  person uuid,
  attrs  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid := save_person.person;
  v_created boolean := save_person.person is null;
  v_row jsonb;
  v_owner uuid;
  v_previous_owner uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_person.tenant, 'parties.write'), false)) then
    raise exception 'not allowed to change companies and people' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  if jsonb_typeof(coalesce(save_person.attrs, '{}')) <> 'object' then
    raise exception 'attrs must be an object' using errcode = '22023', hint = 'PARTY_ATTRS_INVALID';
  end if;
  if save_person.attrs ? 'lifecycle' and not (save_person.attrs ->> 'lifecycle' = any ('{lead,mql,sql,opportunity,customer}'::text[])) then
    raise exception 'unknown lifecycle stage' using errcode = '22023', hint = 'PARTY_LIFECYCLE_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_person_save"(uuid, uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::jsonb)', v_hook::oid::regproc)
        using save_person.tenant, save_person.person, save_person.attrs;
    end if;
  end;
  begin
    if v_created then
      if nullif(trim(save_person.attrs ->> 'name'), '') is null then
        raise exception 'a name is required' using errcode = '23502', hint = 'PARTY_NAME_REQUIRED';
      end if;
      insert into "better_supabase"."people" ("tenant_id", "name", "email", "phone", "title", "lifecycle", "owner_user_id", "user_id", "created_by")
      values (save_person.tenant, nullif(trim(save_person.attrs ->> 'name'), ''), lower(nullif(trim(save_person.attrs ->> 'email'), '')), nullif(trim(save_person.attrs ->> 'phone'), ''), nullif(trim(save_person.attrs ->> 'title'), ''), coalesce(nullif(trim(save_person.attrs ->> 'lifecycle'), ''), ('{lead,mql,sql,opportunity,customer}'::text[])[1]), nullif(save_person.attrs ->> 'ownerId', '')::uuid, nullif(save_person.attrs ->> 'userId', '')::uuid, auth.uid())
      returning "id", "owner_user_id" into v_id, v_owner;
    else
      select x."owner_user_id" into v_previous_owner from "better_supabase"."people" x
      where x."id" = save_person.person and x."tenant_id" = save_person.tenant;
      update "better_supabase"."people" x set "name" = case when save_person.attrs ? 'name' then coalesce(nullif(trim(save_person.attrs ->> 'name'), ''), x."name") else x."name" end,
        "email" = case when save_person.attrs ? 'email' then lower(nullif(trim(save_person.attrs ->> 'email'), '')) else x."email" end,
        "phone" = case when save_person.attrs ? 'phone' then nullif(trim(save_person.attrs ->> 'phone'), '') else x."phone" end,
        "title" = case when save_person.attrs ? 'title' then nullif(trim(save_person.attrs ->> 'title'), '') else x."title" end,
        "lifecycle" = case when save_person.attrs ? 'lifecycle' then coalesce(nullif(trim(save_person.attrs ->> 'lifecycle'), ''), x."lifecycle") else x."lifecycle" end,
        "owner_user_id" = case when save_person.attrs ? 'ownerId' then nullif(save_person.attrs ->> 'ownerId', '')::uuid else x."owner_user_id" end,
        "user_id" = case when save_person.attrs ? 'userId' then nullif(save_person.attrs ->> 'userId', '')::uuid else x."user_id" end,
        "updated_at" = now()
      where x."id" = save_person.person and x."tenant_id" = save_person.tenant and x."merged_into" is null
      returning x."owner_user_id" into v_owner;
      if not found then
        raise exception 'person not found' using errcode = 'P0002', hint = 'PARTY_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'another person has this email' using errcode = '23505', hint = 'PARTY_EMAIL_TAKEN';
  end;
  select to_jsonb(x) into v_row from "better_supabase"."people" x where x."id" = v_id;
  if v_created then
    perform "better_supabase".emit_event('person.created', jsonb_build_object('organizationId', save_person.tenant, 'personId', v_id, 'name', v_row ->> 'name'), 'persons/' || v_id::text, (save_person.tenant::text)::text, null, 'better-supabase/contacts');
  else
    perform "better_supabase".emit_event('person.updated', jsonb_build_object('organizationId', save_person.tenant, 'personId', v_id, 'name', v_row ->> 'name'), 'persons/' || v_id::text, (save_person.tenant::text)::text, null, 'better-supabase/contacts');
  end if;
  if v_owner is not null and v_owner is distinct from v_previous_owner then
    insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
    values (save_person.tenant, v_owner, 'person', v_id::text, 'participating')
    on conflict do nothing;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_person_save"(uuid, boolean)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::boolean)', v_hook::oid::regproc)
        using v_id, v_created;
    end if;
  end;
  return v_row;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_promotion (
  tenant    uuid,
  promotion uuid,
  data      jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_tenant uuid := save_promotion.tenant;
  v_id uuid := save_promotion.promotion;
  v_kind text := data ->> 'kind';
  v_scope text := coalesce(data ->> 'scope', 'order');
  v_currency text := data ->> 'currency';
  v_percent numeric;
  v_targets uuid[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_id is not null then
    select x."tenant_id" into v_tenant from "better_supabase"."promotions" x where x."id" = v_id for update;
    if not found or v_tenant is distinct from save_promotion.tenant then
      raise exception 'promotion not found' using errcode = 'P0002', hint = 'PROMOTIONS_NOT_FOUND';
    end if;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'promotions.manage'), false)) then
    raise exception 'not allowed to manage these promotions' using errcode = '42501', hint = 'PROMOTIONS_FORBIDDEN';
  end if;
  if jsonb_typeof(data) is distinct from 'object' then
    raise exception 'data is an object' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if v_kind is null or v_kind not in ('percentage', 'fixed', 'free_shipping') then
    raise exception 'kind is percentage, fixed or free_shipping' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if v_kind = 'percentage' then
    if coalesce(data ->> 'percent', '') !~ '^[0-9]{1,3}([.][0-9]{1,2})?$' or (data ->> 'percent')::numeric <= 0 or (data ->> 'percent')::numeric > 100 then
      raise exception 'percent is a number above 0 and at most 100, with up to two decimals' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
    end if;
    v_percent := (data ->> 'percent')::numeric;
  end if;
  if v_kind = 'fixed' and ((case when (data ->> 'amount') ~ '^[0-9]{1,18}$' then (data ->> 'amount')::bigint end) is null or (case when (data ->> 'amount') ~ '^[0-9]{1,18}$' then (data ->> 'amount')::bigint end) <= 0) then
    raise exception 'a fixed promotion has an amount above zero' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if data ? 'minSubtotal' and data ->> 'minSubtotal' is not null and ((case when (data ->> 'minSubtotal') ~ '^[0-9]{1,18}$' then (data ->> 'minSubtotal')::bigint end) is null or (case when (data ->> 'minSubtotal') ~ '^[0-9]{1,18}$' then (data ->> 'minSubtotal')::bigint end) <= 0) then
    raise exception 'minSubtotal is an amount above zero' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if (v_kind = 'fixed' or data ->> 'minSubtotal' is not null) and (v_currency is null or "better_supabase"."currency_minor_units"(v_currency) is null) then
    raise exception 'an amount needs an ISO 4217 currency' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if v_scope not in ('order', 'products', 'categories', 'collections') then
    raise exception 'scope is order, products, categories, collections' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if jsonb_typeof(coalesce(data -> 'targets', '[]'::jsonb)) <> 'array' then
    raise exception 'targets is an array of ids' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  select coalesce(array_agg(distinct e::uuid), '{}') into v_targets
  from jsonb_array_elements_text(coalesce(data -> 'targets', '[]'::jsonb)) e;
  if (v_scope = 'order') <> (cardinality(v_targets) = 0) then
    raise exception 'an order promotion has no targets; the other scopes need at least one' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if v_scope <> 'order' and cardinality(v_targets) <> (case v_scope
    when 'products' then (select count(*) from "better_supabase"."products" x where x."id" = any (v_targets) and x."tenant_id" = v_tenant)
    when 'categories' then (select count(*) from "better_supabase"."categories" x where x."id" = any (v_targets) and x."tenant_id" = v_tenant)
    when 'collections' then (select count(*) from "better_supabase"."product_collections" x where x."id" = any (v_targets) and x."tenant_id" = v_tenant)
    else 0 end) then
    raise exception 'every target is a product, category or collection of this organization' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if (data ->> 'startsAt') is not null and (data ->> 'endsAt') is not null
    and (data ->> 'endsAt')::timestamptz <= (data ->> 'startsAt')::timestamptz then
    raise exception 'endsAt is after startsAt' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  if coalesce((data ->> 'usageLimit')::integer, 1) < 1 or coalesce((data ->> 'perCustomerLimit')::integer, 1) < 1 then
    raise exception 'a usage limit is a whole number above zero' using errcode = '22023', hint = 'PROMOTIONS_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_promotion_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  if v_id is null then
    insert into "better_supabase"."promotions" ("tenant_id", "name", "description", "kind", "percent", "currency", "amount", "min_subtotal", "scope", "target_ids", "starts_at", "ends_at", "usage_limit", "per_customer_limit", "stackable", "priority", "automatic", "active")
    values (v_tenant, data ->> 'name', data ->> 'description', v_kind, v_percent, case when v_kind = 'fixed' or data ->> 'minSubtotal' is not null then v_currency end, case when v_kind = 'fixed' then (case when (data ->> 'amount') ~ '^[0-9]{1,18}$' then (data ->> 'amount')::bigint end) end, (case when (data ->> 'minSubtotal') ~ '^[0-9]{1,18}$' then (data ->> 'minSubtotal')::bigint end), v_scope, v_targets, (data ->> 'startsAt')::timestamptz, (data ->> 'endsAt')::timestamptz, (data ->> 'usageLimit')::integer, (data ->> 'perCustomerLimit')::integer, coalesce((data ->> 'stackable')::boolean, false), coalesce((data ->> 'priority')::integer, 0), coalesce((data ->> 'automatic')::boolean, false), coalesce((data ->> 'active')::boolean, true))
    returning "id" into v_id;
  else
    update "better_supabase"."promotions" x set
      "name" = data ->> 'name',
      "description" = data ->> 'description',
      "kind" = v_kind,
      "percent" = v_percent,
      "currency" = case when v_kind = 'fixed' or data ->> 'minSubtotal' is not null then v_currency end,
      "amount" = case when v_kind = 'fixed' then (case when (data ->> 'amount') ~ '^[0-9]{1,18}$' then (data ->> 'amount')::bigint end) end,
      "min_subtotal" = (case when (data ->> 'minSubtotal') ~ '^[0-9]{1,18}$' then (data ->> 'minSubtotal')::bigint end),
      "scope" = v_scope,
      "target_ids" = v_targets,
      "starts_at" = (data ->> 'startsAt')::timestamptz,
      "ends_at" = (data ->> 'endsAt')::timestamptz,
      "usage_limit" = (data ->> 'usageLimit')::integer,
      "per_customer_limit" = (data ->> 'perCustomerLimit')::integer,
      "stackable" = coalesce((data ->> 'stackable')::boolean, false),
      "priority" = coalesce((data ->> 'priority')::integer, 0),
      "automatic" = coalesce((data ->> 'automatic')::boolean, false),
      "active" = coalesce((data ->> 'active')::boolean, true),
      "updated_at" = now()
    where x."id" = v_id;
  end if;
  if coalesce((data ->> 'active')::boolean, true) then
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_promotion_activate"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_promotion_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return jsonb_build_object('id', v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_rule (
  tenant uuid,
  rule   jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_id uuid;
  v_old "better_supabase"."rules";
  v_row "better_supabase"."rules";
  v_subject_type text;
  v_trigger text;
  v_name text;
  v_description text;
  v_conditions jsonb;
  v_actions jsonb;
  v_enabled boolean;
  v_stop boolean;
  v_fields jsonb;
  v_action jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(rule) is distinct from 'object' then
    raise exception 'rule must be an object' using errcode = '22023', hint = 'RULE_INVALID';
  end if;
  v_id := nullif(rule ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from "better_supabase"."rules" x where x."id" = v_id and x."organization_id" = save_rule.tenant for update;
    if v_old."id" is null then
      raise exception 'No rule in this organization has this id' using errcode = 'P0002', hint = 'RULE_NOT_FOUND';
    end if;
    if rule ? 'version' and (rule ->> 'version')::integer is distinct from v_old."version" then
      raise exception 'The rule changed since it was read' using errcode = '40001', hint = 'RULE_CONFLICT';
    end if;
    if rule ? 'subjectType' and rule ->> 'subjectType' is distinct from v_old."subject_type" then
      raise exception 'A rule''s subject type can''t change' using errcode = '22023', hint = 'RULE_INVALID';
    end if;
  end if;
  v_subject_type := coalesce(v_old."subject_type", rule ->> 'subjectType');
  v_trigger := coalesce(rule ->> 'trigger', v_old."trigger");
  v_name := coalesce(nullif(trim(rule ->> 'name'), ''), v_old."name");
  v_description := case when rule ? 'description' then nullif(trim(rule ->> 'description'), '') else v_old."description" end;
  v_conditions := coalesce(rule -> 'conditions', v_old."conditions", '{"id": "root", "type": "group", "combinator": "and", "rules": []}'::jsonb);
  v_actions := coalesce(rule -> 'actions', v_old."actions", '[]'::jsonb);
  v_enabled := coalesce((rule ->> 'enabled')::boolean, v_old."enabled", false);
  v_stop := coalesce((rule ->> 'stopProcessing')::boolean, v_old."stop_processing", false);
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (case when (v_enabled or coalesce(v_old."enabled", false)) then coalesce(better_supabase.can('tenant', save_rule.tenant, 'rules.publish'), false) else coalesce(better_supabase.can('tenant', save_rule.tenant, 'rules.edit'), false) end)) then
    raise exception 'You need % to save this rule', case when (v_enabled or coalesce(v_old."enabled", false)) then '''rules.publish''' else '''rules.edit''' end using errcode = '42501', hint = 'RULE_FORBIDDEN';
  end if;
  if v_subject_type is null or v_subject_type !~ '^[a-z][a-z0-9_]{0,62}$' then
    raise exception 'A rule needs a subject type' using errcode = '22023', hint = 'RULE_INVALID';
  end if;
  if v_trigger is null or length(v_trigger) > 128 or v_trigger !~ '^[a-z][a-z0-9_]*([.:][a-z0-9_]+)*$' then
    raise exception 'A rule needs a trigger such as expense.submitted' using errcode = '22023', hint = 'RULE_INVALID';
  end if;
  if v_name is null or length(v_name) > 200 then
    raise exception 'A rule needs a name of at most 200 characters' using errcode = '22023', hint = 'RULE_INVALID';
  end if;
  v_fields := "better_supabase"."rule_field_map"(v_subject_type);
  if v_fields = '{}'::jsonb then
    raise exception 'No rule fields for %; sync them first', v_subject_type using errcode = '22023', hint = 'RULE_SUBJECT_UNKNOWN';
  end if;
  perform "better_supabase"."rule_check"(v_conditions, v_fields, 1);
  if jsonb_typeof(v_actions) is distinct from 'array' or jsonb_array_length(v_actions) > 20 then
    raise exception 'actions must be an array of at most 20 entries' using errcode = '22023', hint = 'RULE_ACTIONS_INVALID';
  end if;
  for v_action in select x.value from jsonb_array_elements(v_actions) x loop
    if jsonb_typeof(v_action) is distinct from 'object' or v_action ->> 'kind' is null
      or length(v_action ->> 'kind') > 128 or v_action ->> 'kind' !~ '^[a-z][a-z0-9_]*([.][a-z0-9_]+)*$'
      or (v_action ? 'config' and jsonb_typeof(v_action -> 'config') is distinct from 'object') then
      raise exception 'Every action needs a kind such as approvals.request and an optional config object' using errcode = '22023', hint = 'RULE_ACTIONS_INVALID';
    end if;
  end loop;
  if v_old."id" is null then
    insert into "better_supabase"."rules" ("organization_id", "subject_type", "trigger", "name", "description", "conditions", "actions", "enabled", "stop_processing", "rank")
    values (save_rule.tenant, v_subject_type, v_trigger, v_name, v_description, v_conditions, v_actions, v_enabled, v_stop,
      case
    when (select max(x."rank" collate "C") from "better_supabase"."rules" x where x."organization_id" = save_rule.tenant and x."subject_type" = v_subject_type) is null then 'V'
    when length(substring((select max(x."rank" collate "C") from "better_supabase"."rules" x where x."organization_id" = save_rule.tenant and x."subject_type" = v_subject_type) from '^z*')) = length((select max(x."rank" collate "C") from "better_supabase"."rules" x where x."organization_id" = save_rule.tenant and x."subject_type" = v_subject_type)) then (select max(x."rank" collate "C") from "better_supabase"."rules" x where x."organization_id" = save_rule.tenant and x."subject_type" = v_subject_type) || 'V'
    else left((select max(x."rank" collate "C") from "better_supabase"."rules" x where x."organization_id" = save_rule.tenant and x."subject_type" = v_subject_type), length(substring((select max(x."rank" collate "C") from "better_supabase"."rules" x where x."organization_id" = save_rule.tenant and x."subject_type" = v_subject_type) from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr((select max(x."rank" collate "C") from "better_supabase"."rules" x where x."organization_id" = save_rule.tenant and x."subject_type" = v_subject_type), length(substring((select max(x."rank" collate "C") from "better_supabase"."rules" x where x."organization_id" = save_rule.tenant and x."subject_type" = v_subject_type) from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end)
    returning * into v_row;
  elsif v_old."trigger" = v_trigger and v_old."name" = v_name
    and v_old."description" is not distinct from v_description
    and v_old."conditions" = v_conditions and v_old."actions" = v_actions
    and v_old."enabled" = v_enabled and v_old."stop_processing" = v_stop then
    return jsonb_build_object('id', v_old."id", 'organizationId', v_old."organization_id", 'subjectType', v_old."subject_type", 'trigger', v_old."trigger", 'name', v_old."name", 'description', v_old."description", 'conditions', v_old."conditions", 'actions', v_old."actions", 'enabled', v_old."enabled", 'stopProcessing', v_old."stop_processing", 'rank', v_old."rank", 'version', v_old."version", 'createdBy', v_old."created_by", 'updatedBy', v_old."updated_by", 'createdAt', v_old."created_at", 'updatedAt', v_old."updated_at");
  else
    update "better_supabase"."rules" x set
      "trigger" = v_trigger,
      "name" = v_name,
      "description" = v_description,
      "conditions" = v_conditions,
      "actions" = v_actions,
      "enabled" = v_enabled,
      "stop_processing" = v_stop,
      "version" = x."version" + 1,
      "updated_by" = auth.uid(),
      "updated_at" = now()
    where x."id" = v_old."id"
    returning * into v_row;
  end if;
  insert into "better_supabase"."rule_versions" ("rule_id", "version", "organization_id", "name", "conditions", "actions", "saved_by")
  values (v_row."id", v_row."version", v_row."organization_id", v_row."name", v_row."conditions", v_row."actions", auth.uid())
  on conflict do nothing;
  perform "better_supabase".emit_event('rule.saved', jsonb_build_object('organizationId', v_row."organization_id"::text, 'ruleId', v_row."id"::text, 'name', v_row."name", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'version', v_row."version"), 'rules/' || v_row."id"::text, (v_row."organization_id")::text, null, 'better-supabase/automations');
  perform better_supabase.audit_event(
    event_type => 'rule.saved',
    category => 'configuration',
    target_type => 'rule',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'ruleId', v_row."id"::text, 'name', v_row."name", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'version', v_row."version"),
    actor_id => auth.uid()
  );
  if v_row."enabled" and not coalesce(v_old."enabled", false) then
    perform "better_supabase".emit_event('rule.enabled', jsonb_build_object('organizationId', v_row."organization_id"::text, 'ruleId', v_row."id"::text, 'name', v_row."name", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'version', v_row."version"), 'rules/' || v_row."id"::text, (v_row."organization_id")::text, null, 'better-supabase/automations');
  perform better_supabase.audit_event(
    event_type => 'rule.enabled',
    category => 'configuration',
    target_type => 'rule',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'ruleId', v_row."id"::text, 'name', v_row."name", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'version', v_row."version"),
    actor_id => auth.uid()
  );
  elsif not v_row."enabled" and coalesce(v_old."enabled", false) then
    perform "better_supabase".emit_event('rule.disabled', jsonb_build_object('organizationId', v_row."organization_id"::text, 'ruleId', v_row."id"::text, 'name', v_row."name", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'version', v_row."version"), 'rules/' || v_row."id"::text, (v_row."organization_id")::text, null, 'better-supabase/automations');
  perform better_supabase.audit_event(
    event_type => 'rule.disabled',
    category => 'configuration',
    target_type => 'rule',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'ruleId', v_row."id"::text, 'name', v_row."name", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'version', v_row."version"),
    actor_id => auth.uid()
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."organization_id", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'name', v_row."name", 'description', v_row."description", 'conditions', v_row."conditions", 'actions', v_row."actions", 'enabled', v_row."enabled", 'stopProcessing', v_row."stop_processing", 'rank', v_row."rank", 'version', v_row."version", 'createdBy', v_row."created_by", 'updatedBy', v_row."updated_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_work_item_checklist_item (
  work_item      uuid,
  checklist_item uuid,
  attrs          jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."work_items";
  v_id uuid := save_work_item_checklist_item.checklist_item;
  v_last text;
  v_done boolean := (save_work_item_checklist_item.attrs ->> 'done')::boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."work_items" x where x."id" = save_work_item_checklist_item.work_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'work_items.write'), false)) and x."archived_at" is null;
  if v_row."id" is null then
    raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'WORK_ITEM_NOT_FOUND';
  end if;
  begin
    if v_id is null then
      select max(y."rank") into v_last from "better_supabase"."work_item_checklist_items" y where y."work_item_id" = v_row."id";
      insert into "better_supabase"."work_item_checklist_items" ("tenant_id", "work_item_id", "title", "done", "done_at", "done_by", "rank", "created_by")
      values (v_row."tenant_id", v_row."id", trim(save_work_item_checklist_item.attrs ->> 'title'), coalesce(v_done, false),
        case when v_done then now() end, case when v_done then auth.uid() end,
        coalesce(save_work_item_checklist_item.attrs ->> 'rank', case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end), auth.uid())
      returning "id" into v_id;
    else
      update "better_supabase"."work_item_checklist_items" y set
        "title" = coalesce(trim(save_work_item_checklist_item.attrs ->> 'title'), y."title"),
        "rank" = coalesce(save_work_item_checklist_item.attrs ->> 'rank', y."rank"),
        "done" = coalesce(v_done, y."done"),
        "done_at" = case when v_done is null then y."done_at" when v_done then coalesce(y."done_at", now()) end,
        "done_by" = case when v_done is null then y."done_by" when v_done then coalesce(y."done_by", auth.uid()) end
      where y."id" = v_id and y."work_item_id" = v_row."id";
      if not found then
        raise exception 'no such checklist item on this work item' using errcode = 'P0002', hint = 'WORK_ITEM_CHECKLIST_ITEM_NOT_FOUND';
      end if;
    end if;
  exception when check_violation or not_null_violation or invalid_text_representation then
    raise exception 'a checklist item needs a title of 1 to 500 characters and a valid rank' using errcode = '22023', hint = 'WORK_ITEM_CHECKLIST_ITEM_INVALID';
  end;
  perform "better_supabase".emit_event('work_item.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'fields', jsonb_build_array('checklist')), 'work-items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  return (select jsonb_build_object('id', y."id", 'workItemId', y."work_item_id", 'title', y."title", 'done', y."done", 'doneAt', y."done_at", 'doneBy', y."done_by", 'rank', y."rank", 'createdAt', y."created_at") from "better_supabase"."work_item_checklist_items" y where y."id" = v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.schedule_job (
  job_name text,
  schedule text,
  queue    text,
  payload  jsonb                    DEFAULT '{}'::jsonb,
  timezone text                     DEFAULT 'UTC'::text,
  next_run timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  tenant   text                     DEFAULT NULL::text
)
  RETURNS bigint
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  -- pg_cron is optional: its functions are looked up, not named, so
  -- plpgsql_check (supabase db lint) passes without the extension.
  v_schedule regprocedure := pg_catalog.to_regprocedure('cron.schedule(text, text, text)');
  v_id bigint;
begin
  if tenant is not null then
    raise exception 'pg_cron schedules have no tenant; set blocks.queue.options.scheduler to "drain" to keep one per schedule';
  end if;
  if v_schedule is null then
    raise exception 'schedule_job needs pg_cron: create extension pg_cron with schema pg_catalog, or set blocks.queue.options.scheduler to "drain"';
  end if;
  if timezone <> 'UTC' then
    raise exception 'pg_cron runs schedules in cron.timezone, not %; set blocks.queue.options.scheduler to "drain" for per-schedule time zones', timezone;
  end if;
  perform better_supabase.ensure_job_queue(queue);
  execute format('select %s($1::text, $2::text, $3::text)', v_schedule::oid::regproc)
    into v_id
    using job_name, schedule, format('select better_supabase.enqueue_job(%L, %L::jsonb)', queue, payload::text);
  return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_company_person (
  company    uuid,
  person     uuid,
  role       text,
  is_primary boolean
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_role text := nullif(trim(set_company_person.role), '');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."companies" x
  join "better_supabase"."people" p on p."id" = set_company_person.person and p."tenant_id" = x."tenant_id"
  where x."id" = set_company_person.company;
  if v_tenant is null then
    raise exception 'company or person not found in one organization' using errcode = 'P0002', hint = 'PARTY_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'parties.write'), false)) then
    raise exception 'not allowed to change companies and people' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  if coalesce(set_company_person.is_primary, false) then
    update "better_supabase"."company_people" l set "is_primary" = false
    where l."company_id" = set_company_person.company and l."person_id" <> set_company_person.person and l."is_primary";
  end if;
  insert into "better_supabase"."company_people" ("tenant_id", "company_id", "person_id", "role", "is_primary")
  select x."tenant_id", set_company_person.company, set_company_person.person, v_role, coalesce(set_company_person.is_primary, false)
  from "better_supabase"."companies" x where x."id" = set_company_person.company
  on conflict ("company_id", "person_id") do update set "role" = excluded."role", "is_primary" = excluded."is_primary";
  perform "better_supabase".emit_event('company.person_linked', jsonb_build_object('organizationId', v_tenant, 'companyId', set_company_person.company, 'personId', set_company_person.person, 'role', v_role), 'companies/' || set_company_person.company::text, (v_tenant::text)::text, null, 'better-supabase/contacts');
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_flag_override (
  key         text,
  variant     text,
  tenant      uuid DEFAULT NULL::uuid,
  member      uuid DEFAULT NULL::uuid,
  context     text DEFAULT NULL::text,
  context_key text DEFAULT NULL::text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('flags.manage'), false))) then
    raise exception 'Not allowed to manage feature flags' using errcode = '42501', hint = 'FLAGS_FORBIDDEN';
  end if;
  if num_nonnulls(tenant, member, context) <> 1 or (context is null) <> (context_key is null) then
    raise exception 'Pass one target: a tenant, a member, or a context with its key' using errcode = '22023', hint = 'FLAGS_OVERRIDE_TARGET';
  end if;
  if variant is null then
    delete from "better_supabase"."flag_overrides" v
    where v."flag_key" = set_flag_override.key
      and v."organization_id" is not distinct from set_flag_override.tenant
      and v."user_id" is not distinct from set_flag_override.member
      and v."context" is not distinct from set_flag_override.context
      and v."context_key" is not distinct from set_flag_override.context_key;
    if not found then
      return false;
    end if;
    perform "better_supabase".emit_event('flag.override_set', jsonb_build_object('key', set_flag_override.key, 'variant', set_flag_override.variant, 'organizationId', set_flag_override.tenant::text, 'userId', set_flag_override.member, 'context', set_flag_override.context, 'contextKey', set_flag_override.context_key), 'flags/' || set_flag_override.key, (set_flag_override.tenant)::text, null, 'better-supabase/feature-flags');
  perform better_supabase.audit_event(
    event_type => 'flag.override_set',
    category => 'configuration',
    target_type => 'flag',
    record_id => set_flag_override.key,
    tenant => (set_flag_override.tenant)::uuid,
    metadata => jsonb_build_object('key', set_flag_override.key, 'variant', set_flag_override.variant, 'organizationId', set_flag_override.tenant::text, 'userId', set_flag_override.member, 'context', set_flag_override.context, 'contextKey', set_flag_override.context_key)
  );
    return true;
  end if;
  insert into "better_supabase"."flag_overrides" ("flag_key", "organization_id", "user_id", "context", "context_key", "variant")
  values (set_flag_override.key, set_flag_override.tenant, set_flag_override.member, set_flag_override.context, set_flag_override.context_key, set_flag_override.variant)
  on conflict on constraint flag_overrides_unique do update set "variant" = excluded."variant";
  perform "better_supabase".emit_event('flag.override_set', jsonb_build_object('key', set_flag_override.key, 'variant', set_flag_override.variant, 'organizationId', set_flag_override.tenant::text, 'userId', set_flag_override.member, 'context', set_flag_override.context, 'contextKey', set_flag_override.context_key), 'flags/' || set_flag_override.key, (set_flag_override.tenant)::text, null, 'better-supabase/feature-flags');
  perform better_supabase.audit_event(
    event_type => 'flag.override_set',
    category => 'configuration',
    target_type => 'flag',
    record_id => set_flag_override.key,
    tenant => (set_flag_override.tenant)::uuid,
    metadata => jsonb_build_object('key', set_flag_override.key, 'variant', set_flag_override.variant, 'organizationId', set_flag_override.tenant::text, 'userId', set_flag_override.member, 'context', set_flag_override.context, 'contextKey', set_flag_override.context_key)
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_rule_enabled (
  id      uuid,
  enabled boolean
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."rules";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."rules" x where x."id" = set_rule_enabled.id for update;
  if v_row."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'rules.read'), false)) then
    raise exception 'No rule you can read has this id' using errcode = 'P0002', hint = 'RULE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'rules.publish'), false)) then
    raise exception 'Publishing rules needs the publish permission' using errcode = '42501', hint = 'RULE_FORBIDDEN';
  end if;
  if v_row."enabled" = coalesce(set_rule_enabled.enabled, false) then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."organization_id", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'name', v_row."name", 'description', v_row."description", 'conditions', v_row."conditions", 'actions', v_row."actions", 'enabled', v_row."enabled", 'stopProcessing', v_row."stop_processing", 'rank', v_row."rank", 'version', v_row."version", 'createdBy', v_row."created_by", 'updatedBy', v_row."updated_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
  end if;
  update "better_supabase"."rules" x set "enabled" = coalesce(set_rule_enabled.enabled, false), "updated_by" = auth.uid(), "updated_at" = now()
  where x."id" = v_row."id" returning * into v_row;
  if v_row."enabled" then
    perform "better_supabase".emit_event('rule.enabled', jsonb_build_object('organizationId', v_row."organization_id"::text, 'ruleId', v_row."id"::text, 'name', v_row."name", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'version', v_row."version"), 'rules/' || v_row."id"::text, (v_row."organization_id")::text, null, 'better-supabase/automations');
  perform better_supabase.audit_event(
    event_type => 'rule.enabled',
    category => 'configuration',
    target_type => 'rule',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'ruleId', v_row."id"::text, 'name', v_row."name", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'version', v_row."version"),
    actor_id => auth.uid()
  );
  else
    perform "better_supabase".emit_event('rule.disabled', jsonb_build_object('organizationId', v_row."organization_id"::text, 'ruleId', v_row."id"::text, 'name', v_row."name", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'version', v_row."version"), 'rules/' || v_row."id"::text, (v_row."organization_id")::text, null, 'better-supabase/automations');
  perform better_supabase.audit_event(
    event_type => 'rule.disabled',
    category => 'configuration',
    target_type => 'rule',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'ruleId', v_row."id"::text, 'name', v_row."name", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'version', v_row."version"),
    actor_id => auth.uid()
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."organization_id", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'name', v_row."name", 'description', v_row."description", 'conditions', v_row."conditions", 'actions', v_row."actions", 'enabled', v_row."enabled", 'stopProcessing', v_row."stop_processing", 'rank', v_row."rank", 'version', v_row."version", 'createdBy', v_row."created_by", 'updatedBy', v_row."updated_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_service_principal_role (
  principal  uuid,
  role       text,
  created_by uuid DEFAULT NULL::uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."service_principals";
begin
  select * into v_row from "better_supabase"."service_principals" p where p."id" = set_service_principal_role.principal and p."disabled_at" is null for update;
  if not found then
    raise exception 'No such service principal' using errcode = 'P0002', hint = 'SERVICE_PRINCIPAL_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Service principals are managed by the service' using errcode = '42501', hint = 'SERVICE_PRINCIPAL_FORBIDDEN';
  end if;
  if set_service_principal_role.created_by is not null and not (
    coalesce(better_supabase.member_can(set_service_principal_role.created_by, v_row."tenant_id", 'service_principals.manage'), false)
    and coalesce(better_supabase.can_assign_as(set_service_principal_role.created_by, v_row."tenant_id", set_service_principal_role.role), false)
  ) then
    raise exception 'You may not manage service principals with this role' using errcode = '42501', hint = 'SERVICE_PRINCIPAL_FORBIDDEN';
  end if;
  if not (set_service_principal_role.role = any (array['owner', 'admin', 'member']::text[])) then
    raise exception 'Unknown role %', set_service_principal_role.role using errcode = '22023', hint = 'ORGANIZATION_ROLE_UNKNOWN';
  end if;
  update "better_supabase"."service_principals" set "role" = set_service_principal_role.role where "id" = v_row."id";
  perform "better_supabase".emit_event('service_principal.role_changed', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'role', set_service_principal_role.role), 'service-principals/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/service-accounts');
  perform better_supabase.audit_event(
    event_type => 'service_principal.role_changed',
    category => 'access',
    target_type => 'service_principal',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'role', set_service_principal_role.role),
    actor_id => coalesce(set_service_principal_role.created_by, auth.uid())
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_work_item_assignees (
  work_item uuid,
  users     uuid[]
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."work_items";
  v_users uuid[] := array(select distinct x from unnest(coalesce(set_work_item_assignees.users, '{}')) x where x is not null);
  v_new uuid[];
  v_user uuid;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."work_items" x where x."id" = set_work_item_assignees.work_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'work_items.write'), false));
  if v_row."id" is null then
    raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'WORK_ITEM_NOT_FOUND';
  end if;
  v_new := array(select x from unnest(v_users) x where x is distinct from auth.uid() and not exists (
    select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = v_row."id" and y."user_id" = x));
  delete from "better_supabase"."work_item_assignees" y where y."work_item_id" = v_row."id" and not (y."user_id" = any (v_users));
  insert into "better_supabase"."work_item_assignees" ("tenant_id", "work_item_id", "user_id")
  select v_row."tenant_id", v_row."id", x from unnest(v_users) x
  on conflict do nothing;
  foreach v_user in array v_users loop
    insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
    values (v_row."tenant_id", v_user, 'work_item', v_row."id"::text, 'participating')
    on conflict do nothing;
  end loop;
  if cardinality(v_new) > 0 then
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'work_item.assigned',
      'tenant', v_row."tenant_id",
      'actor', auth.uid(),
      'subject_type', 'work_item',
      'subject_id', v_row."id"::text,
      'summary', v_row."title",
      'recipients', to_jsonb(v_new),
      'watchers', false,
      'key', 'work_item.assigned:' || v_row."id"::text || ':' || md5(array_to_string(v_new, ',')),
      'data', jsonb_build_object('workItemId', v_row."id")
    ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  perform "better_supabase".emit_event('work_item.assigned', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'assigneeIds', to_jsonb(v_users)), 'work-items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  return cardinality(v_users);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_work_item_recurrence (
  work_item uuid,
  rrule     text,
  tzid      text DEFAULT 'UTC'::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."work_items";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."work_items" x where x."id" = set_work_item_recurrence.work_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'work_items.write'), false)) and x."archived_at" is null;
  if v_row."id" is null then
    raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'WORK_ITEM_NOT_FOUND';
  end if;
  if set_work_item_recurrence.rrule is null then
    delete from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = v_row."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = v_row."id"::text;
  else
    if set_work_item_recurrence.rrule !~ '^(RRULE:)?FREQ=(DAILY|WEEKLY|MONTHLY|YEARLY)(;[A-Z]+=[-+,0-9A-Z]+)*$' then
      raise exception 'rrule must be an RRULE such as FREQ=WEEKLY;BYDAY=MO' using errcode = '22023', hint = 'WORK_ITEM_RECURRENCE_INVALID';
    end if;
    if not exists (select 1 from pg_catalog.pg_timezone_names z where z.name = coalesce(set_work_item_recurrence.tzid, 'UTC')) then
      raise exception 'tzid must be an IANA time zone' using errcode = '22023', hint = 'WORK_ITEM_RECURRENCE_INVALID';
    end if;
    insert into "better_supabase"."recurrence_rules" ("tenant_id", "subject_type", "subject_id", "dtstart", "tzid", "rrule")
    values (v_row."tenant_id", 'work_item', v_row."id"::text, coalesce(v_row."due_at", now()), coalesce(set_work_item_recurrence.tzid, 'UTC'), regexp_replace(set_work_item_recurrence.rrule, '^RRULE:', ''))
    on conflict ("tenant_id", "subject_type", "subject_id")
    do update set "dtstart" = excluded."dtstart", "tzid" = excluded."tzid", "rrule" = excluded."rrule";
  end if;
  perform "better_supabase".emit_event('work_item.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'fields', jsonb_build_array('recurrence')), 'work-items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) -> 'recurrence' from "better_supabase"."work_items" x where x."id" = v_row."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_engagement (
  engagement uuid,
  attrs      jsonb,
  subjects   jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid := update_engagement.engagement;
  v_tenant uuid;
  v_type text;
  v_title text;
  v_owner uuid;
  v_previous_owner uuid;
  v_item jsonb;
  v_subjects jsonb;
  v_first jsonb;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."type", x."owner_user_id" into v_tenant, v_type, v_previous_owner
  from "better_supabase"."engagements" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'engagements.manage'), false));
  if v_tenant is null then
    raise exception 'no such engagement you can edit' using errcode = 'P0002', hint = 'ENGAGEMENT_NOT_FOUND';
  end if;
  if update_engagement.attrs ? 'type' and not (update_engagement.attrs ->> 'type' = any ('{call,email,meeting,note,task}'::text[])) then
    raise exception 'unknown engagement type' using errcode = '22023', hint = 'ENGAGEMENT_TYPE_INVALID';
  end if;
  update "better_supabase"."engagements" x set
    "type" = coalesce(update_engagement.attrs ->> 'type', x."type"),
    "title" = coalesce(nullif(trim(update_engagement.attrs ->> 'title'), ''), x."title"),
    "body" = case when update_engagement.attrs ? 'body' then update_engagement.attrs ->> 'body' else x."body" end,
    "outcome" = case when update_engagement.attrs ? 'outcome' then update_engagement.attrs ->> 'outcome' else x."outcome" end,
    "external_ref" = case when update_engagement.attrs ? 'externalRef' then update_engagement.attrs ->> 'externalRef' else x."external_ref" end,
    "owner_user_id" = case when update_engagement.attrs ? 'ownerId' then nullif(update_engagement.attrs ->> 'ownerId', '')::uuid else x."owner_user_id" end,
    "due_at" = case when update_engagement.attrs ? 'dueAt' then (update_engagement.attrs ->> 'dueAt')::timestamptz else x."due_at" end,
    "done_at" = case when update_engagement.attrs ? 'doneAt' then (update_engagement.attrs ->> 'doneAt')::timestamptz else x."done_at" end,
    "duration_seconds" = case when update_engagement.attrs ? 'durationSeconds' then (update_engagement.attrs ->> 'durationSeconds')::integer else x."duration_seconds" end,
    "updated_at" = now()
  where x."id" = v_id
  returning x."type", x."title", x."owner_user_id" into v_type, v_title, v_owner;
  if update_engagement.subjects is not null then
    
  if jsonb_typeof(coalesce(update_engagement.subjects, '[]')) <> 'array' then
    raise exception 'subjects must be a list of { type, id }' using errcode = '22023', hint = 'ENGAGEMENT_SUBJECTS_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(update_engagement.subjects, '[]')) loop
    if not (case (v_item ->> 'type')
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'maintenance_request' then exists (select 1 from "better_supabase"."maintenance_requests" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      else false
    end and "better_supabase"."can_subject"((v_item ->> 'type'), (v_item ->> 'id'), 'read')) then
      raise exception 'a subject is unknown or not readable in this organization' using errcode = '42501', hint = 'ENGAGEMENT_SUBJECT_FORBIDDEN';
    end if;
  end loop;
  delete from "better_supabase"."engagement_subjects" x where x."engagement_id" = v_id;
  insert into "better_supabase"."engagement_subjects" ("tenant_id", "engagement_id", "subject_type", "subject_id", "position")
  select v_tenant, v_id, s.value ->> 'type', s.value ->> 'id', s.ordinality::integer
  from jsonb_array_elements(coalesce(update_engagement.subjects, '[]')) with ordinality s
  on conflict do nothing;
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  else
    v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = v_id), '[]'::jsonb);
    v_first := v_subjects -> 0;
  end if;
  perform "better_supabase".emit_event('engagement.updated', jsonb_build_object('organizationId', v_tenant, 'engagementId', v_id, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects), 'engagements/' || v_id::text, (v_tenant::text)::text, null, 'better-supabase/activities');
  if v_owner is not null and v_owner is distinct from auth.uid() and v_owner is distinct from v_previous_owner then
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'engagement.assigned',
      'tenant', v_tenant,
      'actor', auth.uid(),
      'subject_type', v_first ->> 'type',
      'subject_id', v_first ->> 'id',
      'summary', v_title,
      'recipients', jsonb_build_array(v_owner),
      'watchers', false,
      'key', 'engagement.assigned:' || v_id::text || ':' || v_owner::text,
      'data', jsonb_build_object('engagementId', v_id)
    ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."engagements" x where x."id" = v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_work_items (
  changes jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_change jsonb;
  v_item uuid;
  v_field text;
  v_row "better_supabase"."work_items";
  v_accepted jsonb := '[]';
  v_rejected jsonb := '[]';
  v_hint text;
  v_reason text;
  v_touched uuid[] := '{}';
  v_linked integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(coalesce(update_work_items.changes, '[]')) <> 'array' then
    raise exception 'changes must be a list of { workItemId, field, value }' using errcode = '22023', hint = 'WORK_ITEM_CHANGES_INVALID';
  end if;
  for v_change in select value from jsonb_array_elements(update_work_items.changes) loop
    v_field := v_change ->> 'field';
    begin
      v_item := (v_change ->> 'workItemId')::uuid;
      if not exists (select 1 from "better_supabase"."work_items" x where x."id" = v_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'work_items.write'), false)) and x."archived_at" is null) then
        raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'WORK_ITEM_NOT_FOUND';
      end if;
      declare
    v_hook regprocedure := to_regprocedure('"public"."before_work_item_update"(uuid, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::jsonb)', v_hook::oid::regproc)
        using v_item, v_field, v_change -> 'value';
    end if;
  end;
      case v_field
      when 'title' then
        update "better_supabase"."work_items" x set "title" = trim(v_change -> 'value' #>> '{}') where x."id" = v_item;
      when 'body' then
        update "better_supabase"."work_items" x set "body" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_item;
      when 'parentId' then
        update "better_supabase"."work_items" x set "parent_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'teamId' then
        update "better_supabase"."work_items" x set "team_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'projectId' then
        update "better_supabase"."work_items" x set "project_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'iterationId' then
        update "better_supabase"."work_items" x set "iteration_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'priority' then
        update "better_supabase"."work_items" x set "priority" = (v_change -> 'value' #>> '{}')::smallint where x."id" = v_item;
      when 'estimate' then
        update "better_supabase"."work_items" x set "estimate" = (v_change -> 'value' #>> '{}')::numeric where x."id" = v_item;
      when 'progress' then
        update "better_supabase"."work_items" x set "progress" = (v_change -> 'value' #>> '{}')::smallint where x."id" = v_item;
      when 'startAt' then
        update "better_supabase"."work_items" x set "start_at" = (v_change -> 'value' #>> '{}')::timestamptz where x."id" = v_item;
      when 'endAt' then
        update "better_supabase"."work_items" x set "end_at" = (v_change -> 'value' #>> '{}')::timestamptz where x."id" = v_item;
      when 'dueAt' then
        update "better_supabase"."work_items" x set "due_at" = (v_change -> 'value' #>> '{}')::timestamptz where x."id" = v_item;
      when 'stageId' then
        update "better_supabase"."work_items" x set "stage_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_item;
      when 'closeReason' then
        update "better_supabase"."work_items" x set "close_reason" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_item;
      when 'attachments' then
        select * into v_row from "better_supabase"."work_items" x where x."id" = v_item;
        if jsonb_typeof(coalesce((v_change -> 'value'), '[]'::jsonb)) <> 'array' then
      raise exception 'attachments must be a list of attachment ids' using errcode = '22023', hint = 'WORK_ITEM_ATTACHMENTS_INVALID';
    end if;
    if jsonb_array_length(coalesce((v_change -> 'value'), '[]'::jsonb)) > 0 then
      update "better_supabase"."attachments" f set "subject_type" = 'work_item', "subject_id" = v_row."id"::text
      where f."id" = any (array(select jsonb_array_elements_text((v_change -> 'value'))::uuid))
        and f."organization_id" = v_row."tenant_id"
        and (f."subject_type" is null or (f."subject_type" = 'work_item' and f."subject_id" = v_row."id"::text))
        and ((auth.role() = 'service_role') or f."uploaded_by" = auth.uid());
      get diagnostics v_linked = row_count;
      if v_linked <> (select count(distinct x) from jsonb_array_elements_text((v_change -> 'value')) x) then
        raise exception 'attach only your own files in this organization that aren''t on another subject' using errcode = '22023', hint = 'WORK_ITEM_ATTACHMENTS_INVALID';
      end if;
    end if;
      else
        raise exception 'that field can''t be written' using errcode = '22023', hint = 'WORK_ITEM_FIELD_UNKNOWN';
      end case;
      v_accepted := v_accepted || jsonb_build_array(jsonb_build_object('workItemId', v_item, 'field', v_field));
      v_touched := array_append(v_touched, v_item);
      declare
    v_hook regprocedure := to_regprocedure('"public"."after_work_item_update"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_item, v_field;
    end if;
  end;
    exception when others then
      get stacked diagnostics v_hint = pg_exception_hint, v_reason = message_text;
      v_rejected := v_rejected || jsonb_build_array(jsonb_build_object('workItemId', v_change ->> 'workItemId', 'field', v_field, 'hint', nullif(v_hint, ''), 'reason', v_reason));
    end;
  end loop;
  for v_row in select * from "better_supabase"."work_items" x where x."id" = any (v_touched) loop
    perform "better_supabase".emit_event('work_item.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'fields', (select jsonb_agg(distinct a ->> 'field') from jsonb_array_elements(v_accepted) a where (a ->> 'workItemId')::uuid = v_row."id")), 'work-items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  end loop;
  return jsonb_build_object('accepted', v_accepted, 'rejected', v_rejected);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.workflow_runs_alert()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_run "better_supabase"."workflow_runs"%rowtype := new;
  v_alert "better_supabase"."workflow_alerts"%rowtype;
  v_fired integer := 0;
begin
  if new."mode" = 'test' or new."status" <> 'failed' or (tg_op = 'UPDATE' and old."status" = 'failed') then
    return null;
  end if;
  for v_alert in
    select * from "better_supabase"."workflow_alerts" x
    where x."on_event" = 'failed' and x."definition_id"::text = new."attributes" ->> 'bsb.definition'
  loop
    insert into "better_supabase"."workflow_alert_fires" ("alert_id", "run_id") values (v_alert."id", v_run."id")
      on conflict do nothing;
      if found then
        v_fired := v_fired + 1;
        perform "better_supabase".emit_event('workflow_alert.triggered', jsonb_build_object('alertId', v_alert."id", 'organizationId', v_run."tenant_id"::text, 'definition', v_alert."definition_id", 'onEvent', v_alert."on_event", 'channel', v_alert."channel", 'runId', v_run."id", 'status', v_run."status", 'error', v_run."error"), 'workflow-runs/' || v_run."id", (v_run."tenant_id")::text, 'workflow_alert.triggered:' || v_alert."id" || ':' || v_run."id", 'better-supabase/workflow-editor');
      end if;
  end loop;
  return null;
end;
$function$;

ALTER TABLE "better_supabase"."job_openings"
  ADD CONSTRAINT "job_openings_pkey" PRIMARY KEY (id);

ALTER TABLE "better_supabase"."applications"
  ADD CONSTRAINT "applications_job_id_fkey" FOREIGN KEY (job_id) REFERENCES better_supabase.job_openings(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."job_openings"
  ADD CONSTRAINT "job_openings_status_check" CHECK ((status = ANY (ARRAY['draft'::text, 'open'::text, 'closed'::text])));

ALTER TABLE "better_supabase"."job_openings"
  ADD CONSTRAINT "job_openings_title_check" CHECK (((length(title) >= 1) AND (length(title) <= 200)));

ALTER TABLE "better_supabase"."product_collections"
  ADD CONSTRAINT "product_collections_check" CHECK (((kind = 'rule'::text) = (rule IS NOT NULL)));

ALTER TABLE "better_supabase"."product_collections"
  ADD CONSTRAINT "product_collections_kind_check" CHECK ((kind = ANY (ARRAY['manual'::text, 'rule'::text])));

ALTER TABLE "better_supabase"."product_collections"
  ADD CONSTRAINT "product_collections_pkey" PRIMARY KEY (id);

ALTER TABLE "better_supabase"."collection_products"
  ADD CONSTRAINT "collection_products_collection_id_fkey" FOREIGN KEY (collection_id) REFERENCES better_supabase.product_collections(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."product_collections"
  ADD CONSTRAINT "product_collections_slug_check" CHECK ((slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'::text));

ALTER TABLE "better_supabase"."product_collections"
  ADD CONSTRAINT "product_collections_tenant_id_slug_key" UNIQUE (tenant_id, slug);

ALTER TABLE "better_supabase"."product_collections"
  ADD CONSTRAINT "product_collections_title_check" CHECK (((length(title) >= 1) AND (length(title) <= 200)));

CREATE POLICY "product_collections_read" ON "better_supabase"."product_collections"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)));

COMMENT ON FUNCTION "better_supabase"."admission_passes_subject_merge"(text, text, text) IS 'better-supabase:subject-merge';

REVOKE ALL ON FUNCTION "better_supabase"."admission_passes_subject_merge"(text, text, text) FROM PUBLIC;
