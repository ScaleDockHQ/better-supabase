SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.acknowledge_compliance_policy (
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
  select * into v_row from "better_supabase"."policies" x where x."id" = acknowledge_compliance_policy.policy_id;
  if not found then
    raise exception 'policy not found' using errcode = 'P0002', hint = 'COMPLIANCE_POLICY_NOT_FOUND';
  end if;
  if v_me is null or not coalesce(better_supabase.can('tenant', v_row."tenant_id", 'compliance.acknowledge'), false) then
    raise exception 'not allowed to acknowledge policies' using errcode = '42501', hint = 'COMPLIANCE_POLICY_FORBIDDEN';
  end if;
  if v_row."current_version_id" is null or v_row."archived_at" is not null then
    raise exception 'the policy has no published version to acknowledge' using errcode = '55000', hint = 'COMPLIANCE_POLICY_NOT_PUBLISHED';
  end if;
  insert into "better_supabase"."policy_acknowledgements" ("tenant_id", "policy_id", "version_id", "user_id")
  values (v_row."tenant_id", v_row."id", v_row."current_version_id", v_me)
  on conflict ("policy_id", "version_id", "user_id") do nothing;
  if found then
    perform "better_supabase".emit_event('compliance_policy.acknowledged', jsonb_build_object('organizationId', v_row."tenant_id", 'policyId', v_row."id", 'versionId', v_row."current_version_id", 'userId', v_me), 'policies/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/compliance');
  perform better_supabase.audit_event(
    event_type => 'compliance_policy.acknowledged',
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

CREATE OR REPLACE FUNCTION better_supabase.add_organization_domain (
  tenant uuid,
  domain text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."organization_domains";
  v_domain text := lower(trim(trailing '.' from trim(add_organization_domain.domain)));
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not coalesce(better_supabase.can('tenant', add_organization_domain.tenant, 'sso.manage'), false) then
    raise exception 'You may not manage this organization''s domains' using errcode = '42501', hint = 'SSO_FORBIDDEN';
  end if;
  if v_domain !~ '^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?[.])+[a-z]{2,63}$' then
    raise exception 'Not a domain name: %', add_organization_domain.domain using errcode = '22023', hint = 'SSO_DOMAIN_INVALID';
  end if;
  insert into "better_supabase"."organization_domains" as x ("organization_id", "domain") values (add_organization_domain.tenant, v_domain)
  on conflict ("organization_id", "domain") do update set "domain" = x."domain"
  returning * into v_row;
  perform "better_supabase".emit_event('sso_domain.created', jsonb_build_object('organizationId', v_row."organization_id"::text, 'domainId', v_row."id", 'domain', v_row."domain", 'userId', auth.uid()), 'organizations/' || v_row."organization_id"::text, (v_row."organization_id")::text, null, 'better-supabase/sso');
  perform better_supabase.audit_event(
    event_type => 'sso_domain.created',
    category => 'security',
    target_type => 'domain',
    record_id => v_row."id"::text,
    target_label => v_row."domain",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'domainId', v_row."id", 'domain', v_row."domain", 'userId', auth.uid()),
    actor_id => auth.uid()
  );
  return to_jsonb(v_row) - 'verification_token' || jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."domain", 'value', 'better-supabase-domain-verification=' || v_row."verification_token"));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.amend_activity (
  engagement uuid,
  body       text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_from "better_supabase"."engagements";
  v_id uuid;
  v_body text := nullif(trim(amend_activity.body), '');
  v_subjects jsonb;
  v_first jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_from from "better_supabase"."engagements" x
  where x."id" = amend_activity.engagement and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or x."tenant_id" in (select better_supabase.tenant_ids_with('activities.read')) and (
  not exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."engagement_id" = x."id")
  or exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."engagement_id" = x."id" and "better_supabase"."can_subject"(lx."subject_type", lx."subject_id", 'read'))
) and (x."audience" <> 'restricted' or x."tenant_id" in (select better_supabase.tenant_ids_with('activities.read_restricted')) or x."owner_user_id" = (select auth.uid()) or x."created_by" = (select auth.uid()) or exists (select 1 from "better_supabase"."engagement_subjects" nx where nx."engagement_id" = x."id" and "better_supabase"."has_subject_role"(nx."subject_type", nx."subject_id", x."restricted_roles"))));
  if v_from."id" is null then
    raise exception 'no such engagement you can read' using errcode = 'P0002', hint = 'ACTIVITY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_from."tenant_id", 'activities.write'), false)) then
    raise exception 'not allowed to amend engagements' using errcode = '42501', hint = 'ACTIVITY_FORBIDDEN';
  end if;
  if v_body is null then
    raise exception 'an addendum needs a body' using errcode = '23502', hint = 'ACTIVITY_BODY_REQUIRED';
  end if;
  insert into "better_supabase"."engagements" ("tenant_id", "type", "title", "body", "owner_user_id", "amends_id", "audience", "restricted_roles", "category", "goal_id", "locked_at", "created_by")
  values (v_from."tenant_id", v_from."type", v_from."title", v_body, auth.uid(), v_from."id", v_from."audience", v_from."restricted_roles", v_from."category", v_from."goal_id", case when v_from."type"::text = any ('{note,report}'::text[]) then now() + interval '24 hours' end, auth.uid())
  returning "id" into v_id;
  insert into "better_supabase"."engagement_subjects" ("tenant_id", "engagement_id", "subject_type", "subject_id", "position")
  select k."tenant_id", v_id, k."subject_type", k."subject_id", k."position"
  from "better_supabase"."engagement_subjects" k where k."engagement_id" = v_from."id";
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  perform "better_supabase".emit_event('activity.amended', jsonb_build_object('organizationId', v_from."tenant_id", 'engagementId', v_id, 'type', v_from."type"::text, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects, 'amendsId', v_from."id"), 'engagements/' || v_id::text, (v_from."tenant_id"::text)::text, null, 'better-supabase/activities');
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."engagements" x where x."id" = v_id);
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
  where x."id" = archive_work_item.work_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false))
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  if archive_work_item.archived then
    perform "better_supabase".emit_event('task.archived', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title"), 'work-items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  end if;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.attach_activity_recording (
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
  from "better_supabase"."engagements" x where x."id" = attach_activity_recording.engagement and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false));
  if v_tenant is null then
    raise exception 'no such engagement you can edit' using errcode = 'P0002', hint = 'ACTIVITY_NOT_FOUND';
  end if;
  if not exists (
    select 1 from "better_supabase"."ai_files" fx
    where fx."id" = attach_activity_recording.file
      and fx."organization_id"::text = v_tenant::text
      and fx."status" = 'ready'
      and (auth.role() = 'service_role' or fx."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_tenant, 'activities.manage'), false))
  ) then
    raise exception 'no such ready file in this organization' using errcode = 'P0002', hint = 'AI_FILE_NOT_FOUND';
  end if;
  insert into "better_supabase"."engagement_recordings" ("tenant_id", "engagement_id", "file_id", "filename", "media_type", "language", "created_by")
  select v_tenant, attach_activity_recording.engagement, fx."id", fx."filename", fx."media_type", nullif(trim(attach_activity_recording.language), ''), auth.uid()
  from "better_supabase"."ai_files" fx where fx."id" = attach_activity_recording.file
  on conflict ("engagement_id", "file_id") do nothing
  returning "id" into v_recording;
  if v_recording is null then
    raise exception 'the file is already a recording of this engagement' using errcode = '23505', hint = 'ACTIVITY_RECORDING_EXISTS';
  end if;
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = attach_activity_recording.engagement), '[]'::jsonb);
  v_first := v_subjects -> 0;
  perform "better_supabase".emit_event('activity.recorded', jsonb_build_object('organizationId', v_tenant, 'engagementId', attach_activity_recording.engagement, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects, 'recordingId', v_recording), 'engagements/' || attach_activity_recording.engagement::text, (v_tenant::text)::text, null, 'better-supabase/activities');
  perform "better_supabase"."enqueue_job"(queue => 'engagements.transcribe', payload => jsonb_build_object('recordingId', v_recording), dedupe_key => 'engagements.transcribe:' || v_recording::text, dedupe_running => false);
  return (select jsonb_build_object('id', rx."id", 'organizationId', rx."tenant_id", 'engagementId', rx."engagement_id", 'fileId', rx."file_id", 'filename', rx."filename", 'mediaType', rx."media_type", 'status', rx."status", 'language', rx."language", 'durationSeconds', rx."duration_seconds", 'error', rx."error", 'model', rx."model", 'segmentCount', (select count(*)::integer from "better_supabase"."engagement_transcript_segments" sc where sc."recording_id" = rx."id"), 'createdBy', rx."created_by", 'createdAt', rx."created_at", 'transcribedAt', rx."transcribed_at") from "better_supabase"."engagement_recordings" rx where rx."id" = v_recording);
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
    values (v_tenant, 'meeting', coalesce(v_title, 'Booking'), new."notes", v_owner, lower(new."during"), extract(epoch from upper(new."during") - lower(new."during"))::integer, v_ref, new."created_by")
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
      perform "better_supabase".emit_event('activity.logged', jsonb_build_object('organizationId', v_tenant, 'engagementId', v_id, 'type', 'meeting', 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects), 'engagements/' || v_id::text, (v_tenant::text)::text, null, 'better-supabase/activities');
    else
      perform "better_supabase".emit_event('activity.updated', jsonb_build_object('organizationId', v_tenant, 'engagementId', v_id, 'type', 'meeting', 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects), 'engagements/' || v_id::text, (v_tenant::text)::text, null, 'better-supabase/activities');
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
      perform "better_supabase".emit_event('activity.completed', jsonb_build_object('organizationId', v_tenant, 'engagementId', v_id, 'type', 'meeting', 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects), 'engagements/' || v_id::text, (v_tenant::text)::text, null, 'better-supabase/activities');
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
      raise exception 'an item can''t sit under itself' using errcode = '23514', hint = 'TASK_PARENT_CYCLE';
    end if;
    if not exists (select 1 from "better_supabase"."work_items" x where x."id" = new."parent_id" and x."tenant_id" = new."tenant_id") then
      raise exception 'the parent is in another organization' using errcode = '22023', hint = 'TASK_PARENT_INVALID';
    end if;
  end if;
  if tg_op = 'UPDATE' and old."locked" and not (auth.role() = 'service_role') and (new."start_at" is distinct from old."start_at" or new."end_at" is distinct from old."end_at" or new."due_at" is distinct from old."due_at") then
    raise exception 'the item is locked; its dates can''t change' using errcode = '55000', hint = 'TASK_LOCKED';
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
      perform "better_supabase".emit_event('task.closed', jsonb_build_object('organizationId', new."tenant_id", 'workItemId', new."id", 'subjectType', 'work_item', 'subjectId', new."id"::text, 'title', new."title", 'state', new."state", 'closeReason', new."close_reason"), 'work-items/' || new."id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/tasks');
    elsif not (new."state" in ('completed', 'canceled')) and old."state" in ('completed', 'canceled') then
      new."closed_at" := null;
      new."close_reason" := null;
      perform "better_supabase".emit_event('task.reopened', jsonb_build_object('organizationId', new."tenant_id", 'workItemId', new."id", 'subjectType', 'work_item', 'subjectId', new."id"::text, 'title', new."title"), 'work-items/' || new."id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/tasks');
    end if;
  end if;
  new."updated_at" := now();
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.cancel_signature_request (
  request_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_req "better_supabase"."signature_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_req from "better_supabase"."signature_requests" x where x."id" = cancel_signature_request.request_id for update;
  if not found then
    raise exception 'signature request not found' using errcode = 'P0002', hint = 'SIGNATURE_REQUEST_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_req."requested_by" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_req."tenant_id", 'signatures.manage'), false)) then
    raise exception 'not allowed to cancel this request' using errcode = '42501', hint = 'SIGNATURE_FORBIDDEN';
  end if;
  if v_req."status" <> 'pending' then
    raise exception 'this request is no longer pending' using errcode = '22023', hint = 'SIGNATURE_REQUEST_CLOSED';
  end if;
  update "better_supabase"."signature_requests" x set "status" = 'cancelled', "completed_at" = now()
    where x."id" = v_req."id"
    returning * into v_req;
  perform "better_supabase".emit_event('signature_request.cancelled', jsonb_build_object('organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id"), 'signature-requests/' || v_req."id"::text, (v_req."tenant_id")::text, null, 'better-supabase/signatures');
  perform better_supabase.audit_event(
    event_type => 'signature_request.cancelled',
    category => 'data',
    target_type => 'signature_request',
    record_id => v_req."id"::text,
    summary => 'cancelled a signature request',
    tenant => (v_req."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id")
  );
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'versionId', v_req."version_id", 'contentHash', v_req."content_hash", 'signers', to_jsonb(v_req."signers"), 'order', v_req."sign_order", 'status', v_req."status", 'approvalRequestId', v_req."approval_request_id", 'message', v_req."message", 'meaning', v_req."meaning", 'requestedBy', v_req."requested_by", 'createdAt', v_req."created_at", 'completedAt', v_req."completed_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.complete_activity (
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
  v_id uuid := complete_activity.engagement;
  v_tenant uuid;
  v_type text;
  v_subjects jsonb := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = complete_activity.engagement), '[]'::jsonb);
  v_first jsonb := v_subjects -> 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if exists (select 1 from "better_supabase"."engagements" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the engagement is locked: add an addendum with amend_activity instead' using errcode = '55000', hint = 'ACTIVITY_LOCKED';
  end if;
  update "better_supabase"."engagements" x set
    "done_at" = case when complete_activity.done then coalesce(x."done_at", now()) end,
    "outcome" = coalesce(complete_activity.outcome, x."outcome"),
    "updated_at" = now()
  where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false))
  returning x."tenant_id", x."type" into v_tenant, v_type;
  if v_tenant is null then
    raise exception 'no such engagement you can edit' using errcode = 'P0002', hint = 'ACTIVITY_NOT_FOUND';
  end if;
  if complete_activity.done then
    perform "better_supabase".emit_event('activity.completed', jsonb_build_object('organizationId', v_tenant, 'engagementId', v_id, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects), 'engagements/' || v_id::text, (v_tenant::text)::text, null, 'better-supabase/activities');
  end if;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."engagements" x where x."id" = v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.complete_webhook_delivery (
  delivery uuid,
  outcome  jsonb
)
  RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_status text := complete_webhook_delivery.outcome ->> 'status';
  v_attempt integer := (complete_webhook_delivery.outcome ->> 'attempt')::integer;
  v_endpoint uuid;
  v_tenant uuid;
  v_since timestamptz;
  v_result text := 'ok';
begin
  if v_status is null or v_status not in ('succeeded', 'retrying', 'dead', 'canceled') then
    raise exception 'status must be succeeded, retrying, dead or canceled' using errcode = '22023', hint = 'WEBHOOK_STATUS_UNKNOWN';
  end if;
  if v_attempt is null then
    raise exception 'outcome.attempt must be the attempt the claim returned' using errcode = '22023', hint = 'WEBHOOK_ATTEMPT_REQUIRED';
  end if;
  update "better_supabase"."webhook_deliveries" v
  set "status" = v_status,
    "attempt" = case when v_status = 'canceled' then greatest(v."attempt" - 1, 0) else v."attempt" end,
    "available_at" = case when v_status = 'retrying' then coalesce((complete_webhook_delivery.outcome ->> 'retry_at')::timestamptz, now()) else v."available_at" end,
    "leased_until" = null,
    "response_status" = (complete_webhook_delivery.outcome ->> 'response_status')::integer,
    "response_body" = complete_webhook_delivery.outcome ->> 'response_body',
    "duration_ms" = (complete_webhook_delivery.outcome ->> 'duration_ms')::integer,
    "last_error" = complete_webhook_delivery.outcome ->> 'error',
    "processed_at" = case when v_status = 'retrying' then null else now() end,
    "updated_at" = now()
  where v."id" = complete_webhook_delivery.delivery
    and v."attempt" = v_attempt
    and v."status" = 'delivering'
  returning v."endpoint_id" into v_endpoint;
  if not found then
    if exists (select 1 from "better_supabase"."webhook_deliveries" v where v."id" = complete_webhook_delivery.delivery) then
      return 'stale';
    end if;
    raise exception 'Webhook delivery not found' using errcode = 'P0002', hint = 'WEBHOOK_DELIVERY_NOT_FOUND';
  end if;
  if v_status = 'succeeded' then
    update "better_supabase"."webhook_endpoints" d set "failing_since" = null
    where d."id" = v_endpoint and d."failing_since" is not null;
  elsif v_status in ('retrying', 'dead') then
    update "better_supabase"."webhook_endpoints" d set "failing_since" = coalesce(d."failing_since", now())
    where d."id" = v_endpoint
    returning d."failing_since", d."organization_id" into v_since, v_tenant;
    if v_since <= now() - '5 days'::interval then
      update "better_supabase"."webhook_endpoints" d set "enabled" = false, "disabled_at" = now(), "disabled_reason" = format('Deliveries failed since %s', v_since), "updated_at" = now()
      where d."id" = v_endpoint and d."enabled";
      if found then
        v_result := 'disabled';
        perform "better_supabase".emit_event('webhook_endpoint.disabled', jsonb_build_object('endpointId', v_endpoint, 'organizationId', v_tenant::text, 'failingSince', v_since), 'webhooks/' || v_endpoint::text, (v_tenant::text)::text, 'webhook_endpoint.disabled:' || v_endpoint::text || ':' || v_since::text, 'better-supabase/webhooks-out');
  perform better_supabase.audit_event(
    event_type => 'webhook_endpoint.disabled',
    category => 'integration',
    target_type => 'webhook_endpoint',
    record_id => v_endpoint::text,
    tenant => (v_tenant::text)::uuid,
    metadata => jsonb_build_object('endpointId', v_endpoint, 'organizationId', v_tenant::text, 'failingSince', v_since),
    idempotency_key => 'webhook_endpoint.disabled:' || v_endpoint::text || ':' || v_since::text
  );
      end if;
    end if;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_webhook_delivery"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using complete_webhook_delivery.delivery, v_status;
    end if;
  end;
  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_signature_request (
  tenant              uuid,
  subject_type        text,
  subject_id          text,
  signers             uuid[],
  version_id          uuid   DEFAULT NULL::uuid,
  sign_order          text   DEFAULT 'parallel'::text,
  approval_request_id uuid   DEFAULT NULL::uuid,
  message             text   DEFAULT NULL::text,
  meaning             text   DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_version uuid := create_signature_request.version_id;
  v_hash text;
  v_row "better_supabase"."signature_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'signatures.request'), false) and case create_signature_request.subject_type
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'contacts.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'contacts.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'posts.read'), false)
    when 'activity' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'activities.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'tasks.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'compliance.read'), false)
    when 'compliance_policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'compliance.read'), false)
    when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'qualifications.read'), false)
    when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'risks.read'), false)
    when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'care_plans.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'content.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'forms.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (create_signature_request.subject_id)::uuid and s."organization_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant and (coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (create_signature_request.subject_id)::uuid and s."organization_id" = create_signature_request.tenant)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (create_signature_request.subject_id)::uuid and s."organization_id" = create_signature_request.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (create_signature_request.subject_id)::uuid and s."organization_id" = create_signature_request.tenant)
    else false
  end)) then
    raise exception 'not allowed to request signatures on this record' using errcode = '42501', hint = 'SIGNATURE_FORBIDDEN';
  end if;
  if create_signature_request.meaning is not null and create_signature_request.meaning not in ('authored', 'reviewed', 'approved', 'released', 'acknowledged', 'agreed') then
    raise exception 'meaning must be one of authored, reviewed, approved, released, acknowledged, agreed' using errcode = '22023', hint = 'SIGNATURE_REQUEST_MEANING_UNKNOWN';
  end if;
  if create_signature_request.sign_order not in ('parallel', 'sequential') then
    raise exception 'sign_order must be parallel or sequential' using errcode = '22023', hint = 'SIGNATURE_ORDER_INVALID';
  end if;
  if coalesce(cardinality(create_signature_request.signers), 0) not between 1 and 20
    or array_position(create_signature_request.signers, null) is not null
    or (select count(distinct x) from unnest(create_signature_request.signers) x) <> cardinality(create_signature_request.signers) then
    raise exception 'name between 1 and 20 different signers' using errcode = '22023', hint = 'SIGNATURE_SIGNERS_INVALID';
  end if;
  if exists (
    select 1 from unnest(create_signature_request.signers) x
    where not exists (
      select 1 from "public"."memberships" m
      where m."organization_id" = create_signature_request.tenant and m."user_id" = x
    )
  ) then
    raise exception 'every signer must be a member of the organization' using errcode = '22023', hint = 'SIGNATURE_SIGNERS_INVALID';
  end if;
  if create_signature_request.approval_request_id is not null and not exists (
    select 1 from "better_supabase"."approval_requests" a
    where a."id" = create_signature_request.approval_request_id
      and a."tenant_id" = create_signature_request.tenant
      and a."subject_type" = create_signature_request.subject_type
      and a."subject_id" = create_signature_request.subject_id
  ) then
    raise exception 'the approval request isn''t for this record' using errcode = '22023', hint = 'SIGNATURE_APPROVAL_NOT_FOUND';
  end if;
  if v_version is null then
    v_version := ("better_supabase"."snapshot_version"(create_signature_request.tenant, create_signature_request.subject_type, create_signature_request.subject_id) ->> 'id')::uuid;
  end if;
  select x."content_hash" into v_hash
    from "better_supabase"."versions" x
    where x."id" = v_version
      and x."tenant_id" = create_signature_request.tenant
      and x."subject_type" = create_signature_request.subject_type
      and x."subject_id" = create_signature_request.subject_id;
  if v_hash is null then
    raise exception 'the version isn''t a version of this record' using errcode = '22023', hint = 'SIGNATURE_VERSION_NOT_FOUND';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_signature_request"(uuid, text, text, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::uuid)', v_hook::oid::regproc)
        using create_signature_request.tenant, create_signature_request.subject_type, create_signature_request.subject_id, v_version;
    end if;
  end;
  update "better_supabase"."versions" x set "frozen" = true where x."id" = v_version and not x."frozen";
  insert into "better_supabase"."signature_requests" ("tenant_id", "subject_type", "subject_id", "version_id", "content_hash", "signers", "sign_order", "approval_request_id", "message", "meaning", "requested_by")
  values (create_signature_request.tenant, create_signature_request.subject_type, create_signature_request.subject_id, v_version, v_hash, create_signature_request.signers, create_signature_request.sign_order, create_signature_request.approval_request_id, nullif(trim(create_signature_request.message), ''), create_signature_request.meaning, auth.uid())
  returning * into v_row;
  perform "better_supabase".emit_event('signature_request.requested', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'id', v_row."id", 'versionId', v_row."version_id"), 'signature-requests/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/signatures');
  perform better_supabase.audit_event(
    event_type => 'signature_request.requested',
    category => 'data',
    target_type => 'signature_request',
    record_id => v_row."id"::text,
    summary => 'requested signatures on ' || v_row."subject_type" || ' ' || v_row."subject_id",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'id', v_row."id", 'versionId', v_row."version_id")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_signature_request"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'versionId', v_row."version_id", 'contentHash', v_row."content_hash", 'signers', to_jsonb(v_row."signers"), 'order', v_row."sign_order", 'status', v_row."status", 'approvalRequestId', v_row."approval_request_id", 'message', v_row."message", 'meaning', v_row."meaning", 'requestedBy', v_row."requested_by", 'createdAt', v_row."created_at", 'completedAt', v_row."completed_at");
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
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', create_work_item.tenant, 'tasks.write'), false)) then
    raise exception 'not allowed to change work items' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  if nullif(trim(create_work_item.attrs ->> 'title'), '') is null then
    raise exception 'a title is required' using errcode = '23502', hint = 'TASK_TITLE_REQUIRED';
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
    raise exception 'a work item field has an invalid value' using errcode = '22023', hint = 'TASK_ATTRS_INVALID';
  end;
  if cardinality(coalesce(create_work_item.assignees, '{}')) > 0 then
    perform "better_supabase"."set_work_item_assignees"(v_id, create_work_item.assignees);
  end if;
  select * into v_row from "better_supabase"."work_items" x where x."id" = v_id;
  if jsonb_typeof(coalesce((create_work_item.attrs -> 'attachments'), '[]'::jsonb)) <> 'array' then
      raise exception 'attachments must be a list of attachment ids' using errcode = '22023', hint = 'TASK_ATTACHMENTS_INVALID';
    end if;
    if jsonb_array_length(coalesce((create_work_item.attrs -> 'attachments'), '[]'::jsonb)) > 0 then
      update "better_supabase"."attachments" f set "subject_type" = 'work_item', "subject_id" = v_row."id"::text
      where f."id" = any (array(select jsonb_array_elements_text((create_work_item.attrs -> 'attachments'))::uuid))
        and f."organization_id" = v_row."tenant_id"
        and (f."subject_type" is null or (f."subject_type" = 'work_item' and f."subject_id" = v_row."id"::text))
        and ((auth.role() = 'service_role') or f."uploaded_by" = auth.uid());
      get diagnostics v_linked = row_count;
      if v_linked <> (select count(distinct x) from jsonb_array_elements_text((create_work_item.attrs -> 'attachments')) x) then
        raise exception 'attach only your own files in this organization that aren''t on another subject' using errcode = '22023', hint = 'TASK_ATTACHMENTS_INVALID';
      end if;
    end if;
  perform "better_supabase".emit_event('task.created', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title"), 'work-items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
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

CREATE OR REPLACE FUNCTION better_supabase.credential_set (
  provider    text,
  name        text,
  secret      text,
  description text DEFAULT NULL::text
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role reads and writes credentials'
      using errcode = '42501', hint = 'CREDENTIALS_FORBIDDEN';
  end if;
  if credential_set.provider !~ '^[a-z][a-z0-9-]{0,39}$' or credential_set.name !~ '^[A-Za-z0-9][A-Za-z0-9:._/@-]{0,199}$' then
    raise exception 'credential names are a provider and a name of letters, digits and :._/@-'
      using errcode = 'P0001', hint = 'CREDENTIAL_NAME_INVALID';
  end if;
  if credential_set.secret is null or length(credential_set.secret) = 0 then
    raise exception 'a credential needs a value'
      using errcode = 'P0001', hint = 'CREDENTIAL_EMPTY';
  end if;
  select s.id into v_id from vault.secrets s where s.name = 'bs:cred:' || credential_set.provider || ':' || credential_set.name;
  if v_id is null then
    v_id := vault.create_secret(
      credential_set.secret,
      'bs:cred:' || credential_set.provider || ':' || credential_set.name,
      coalesce(credential_set.description, 'better-supabase credential')
    );
  else
    perform vault.update_secret(v_id, credential_set.secret);
  end if;
  perform "better_supabase".emit_event('credential.updated', jsonb_build_object('provider', credential_set.provider, 'name', credential_set.name), 'credentials/' || credential_set.provider || '/' || credential_set.name, null, null, 'better-supabase/credentials');
  perform better_supabase.audit_event(
    event_type => 'credential.updated',
    category => 'security',
    target_type => 'credential',
    record_id => credential_set.provider || ':' || credential_set.name,
    metadata => jsonb_build_object('provider', credential_set.provider, 'name', credential_set.name)
  );
  return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.decide_waitlist_entry (
  id      uuid,
  approve boolean
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."waitlist_entries";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('waitlist.manage'), false))) then
    raise exception 'You may not manage the waitlist' using errcode = '42501', hint = 'WAITLIST_FORBIDDEN';
  end if;
  update "better_supabase"."waitlist_entries" x set
    "status" = case when decide_waitlist_entry.approve then 'approved' else 'rejected' end,
    "decided_by" = auth.uid(),
    "decided_at" = now()
  where x."id" = decide_waitlist_entry.id and x."status" in ('waiting', 'approved', 'rejected')
  returning * into v_row;
  if v_row."id" is null then
    raise exception 'No open waitlist entry %', decide_waitlist_entry.id using errcode = 'P0002', hint = 'WAITLIST_NOT_FOUND';
  end if;
  if decide_waitlist_entry.approve then
    perform "better_supabase".emit_event('waitlist_entry.approved', jsonb_build_object('entryId', v_row."id"::text, 'email', v_row."email"), 'waitlist-entries/' || v_row."id"::text, null, null, 'better-supabase/waitlist');
  perform better_supabase.audit_event(
    event_type => 'waitlist_entry.approved',
    category => 'access',
    target_type => 'waitlist_entry',
    record_id => v_row."id"::text,
    target_label => v_row."email",
    metadata => jsonb_build_object('entryId', v_row."id"::text, 'email', v_row."email")
  );
  else
    perform "better_supabase".emit_event('waitlist_entry.rejected', jsonb_build_object('entryId', v_row."id"::text, 'email', v_row."email"), 'waitlist-entries/' || v_row."id"::text, null, null, 'better-supabase/waitlist');
  perform better_supabase.audit_event(
    event_type => 'waitlist_entry.rejected',
    category => 'access',
    target_type => 'waitlist_entry',
    record_id => v_row."id"::text,
    target_label => v_row."email",
    metadata => jsonb_build_object('entryId', v_row."id"::text, 'email', v_row."email")
  );
  end if;
  return to_jsonb(v_row);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.decline_signature_request (
  request_id uuid,
  reason     text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_me uuid := auth.uid();
  v_req "better_supabase"."signature_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_req from "better_supabase"."signature_requests" x where x."id" = decline_signature_request.request_id for update;
  if not found then
    raise exception 'signature request not found' using errcode = 'P0002', hint = 'SIGNATURE_REQUEST_NOT_FOUND';
  end if;
  if v_me is null or not (v_me = any (v_req."signers")) then
    raise exception 'not a signer on this request' using errcode = '42501', hint = 'SIGNATURE_FORBIDDEN';
  end if;
  if v_req."status" <> 'pending' then
    raise exception 'this request is no longer pending' using errcode = '22023', hint = 'SIGNATURE_REQUEST_CLOSED';
  end if;
  update "better_supabase"."signature_requests" x set "status" = 'declined', "completed_at" = now()
    where x."id" = v_req."id"
    returning * into v_req;
  perform "better_supabase".emit_event('signature_request.declined', jsonb_build_object('organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'signer', v_me), 'signature-requests/' || v_req."id"::text, (v_req."tenant_id")::text, null, 'better-supabase/signatures');
  perform better_supabase.audit_event(
    event_type => 'signature_request.declined',
    category => 'data',
    target_type => 'signature_request',
    record_id => v_req."id"::text,
    summary => 'declined to sign' || coalesce(': ' || left(decline_signature_request.reason, 200), ''),
    tenant => (v_req."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'signer', v_me)
  );
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'versionId', v_req."version_id", 'contentHash', v_req."content_hash", 'signers', to_jsonb(v_req."signers"), 'order', v_req."sign_order", 'status', v_req."status", 'approvalRequestId', v_req."approval_request_id", 'message', v_req."message", 'meaning', v_req."meaning", 'requestedBy', v_req."requested_by", 'createdAt', v_req."created_at", 'completedAt', v_req."completed_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_activity (
  engagement uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid := delete_activity.engagement;
  v_tenant uuid;
  v_type text;
  v_subjects jsonb := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = delete_activity.engagement), '[]'::jsonb);
  v_first jsonb := v_subjects -> 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if exists (select 1 from "better_supabase"."engagements" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the engagement is locked: add an addendum with amend_activity instead' using errcode = '55000', hint = 'ACTIVITY_LOCKED';
  end if;
  delete from "better_supabase"."engagements" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false))
  returning x."tenant_id", x."type" into v_tenant, v_type;
  if v_tenant is null then
    return false;
  end if;
  perform "better_supabase".emit_event('activity.deleted', jsonb_build_object('organizationId', v_tenant, 'engagementId', v_id, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects), 'engagements/' || v_id::text, (v_tenant::text)::text, null, 'better-supabase/activities');
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_field_definition (
  definition uuid
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
  select "tenant_id" into v_tenant from "better_supabase"."field_definitions" where "id" = delete_field_definition.definition;
  if not found then
    raise exception 'field not found' using errcode = 'P0002', hint = 'FIELD_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'custom_fields.manage'), false)) then
    raise exception 'not allowed to manage custom fields' using errcode = '42501', hint = 'FIELD_FORBIDDEN';
  end if;
  delete from "better_supabase"."field_definitions" where "id" = delete_field_definition.definition;
  perform "better_supabase".emit_event('field_definition.deleted', jsonb_build_object('organizationId', v_tenant, 'id', delete_field_definition.definition), 'custom-fields/' || delete_field_definition.definition::text, (v_tenant)::text, null, 'better-supabase/custom-fields');
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_variant (
  variant uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_product uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."product_id" into v_tenant, v_product from "better_supabase"."product_variants" x where x."id" = delete_variant.variant;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  if exists (select 1 from "better_supabase"."ledger_accounts" sa where sa."managed_by" = 'inventory' and sa."kind" = 'stock' and (case when sa."kind" = 'stock' then (sa."metadata" ->> 'variantId')::uuid end) in (delete_variant.variant)) then
    raise exception 'the stock ledger has movements for this record; archive it instead' using errcode = '23503', hint = 'CATALOG_VARIANT_IN_USE';
  end if;
  delete from "better_supabase"."product_variants" x where x."id" = delete_variant.variant;
  perform "better_supabase".emit_event('product_variant.deleted', jsonb_build_object('organizationId', v_tenant, 'id', delete_variant.variant, 'productId', v_product), 'variants/' || delete_variant.variant::text, (v_tenant)::text, null, 'better-supabase/catalog');
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
    and ((auth.role() = 'service_role') or x."created_by" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.manage'), false))
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  perform "better_supabase".emit_event('task.deleted', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title"), 'work-items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
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
  where y."id" = delete_work_item_checklist_item.checklist_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false)) and x."archived_at" is null;
  if v_row."id" is null then
    return false;
  end if;
  delete from "better_supabase"."work_item_checklist_items" y where y."id" = delete_work_item_checklist_item.checklist_item;
  perform "better_supabase".emit_event('task.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'fields', jsonb_build_array('checklist')), 'work-items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_document_obsolete (
  node   uuid,
  reason text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
begin
  perform better_supabase.raise_actor_readonly() where not better_supabase.actor_may_write();
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_document_obsolete.node and x."deleted_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if v_node."kind" <> 'file' then
    raise exception 'only a file can be obsoleted' using errcode = '22023', hint = 'DRIVE_NOT_A_FILE';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'owner')) then
    raise exception 'not allowed to withdraw this document' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (v_node."locked_until" > now() and v_node."locked_by" is distinct from auth.uid() and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'this item is checked out by someone else' using errcode = '55P03', hint = 'DRIVE_LOCKED', detail = jsonb_build_object('lockedBy', v_node."locked_by", 'lockedUntil', v_node."locked_until")::text;
  end if;
  if v_node."document_status" is distinct from 'effective' then
    raise exception 'only an effective document can be made obsolete' using errcode = '22023', hint = 'DRIVE_DOCUMENT_STATUS_INVALID';
  end if;
  perform "better_supabase"."transition"('drive_node', v_node."id"::text, 'obsolete', drive_document_obsolete.reason);
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = v_node."id";
  perform "better_supabase".emit_event('drive_node.obsoleted', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'documentNumber', v_node."document_number", 'reason', drive_document_obsolete.reason), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive-files');
  perform better_supabase.audit_event(
    event_type => 'drive_node.obsoleted',
    category => 'data',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'document made obsolete',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'documentNumber', v_node."document_number", 'reason', drive_document_obsolete.reason)
  );
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_document_release (
  node       uuid,
  attachment uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_file "better_supabase"."attachments"%rowtype;
  v_version uuid;
  v_inserted jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or exists (
    select 1 from "better_supabase"."approval_requests" q
    where q."id"::text = nullif(current_setting('better_supabase.approval', true), '')
      and q."status" = 'approved' and q."action" = 'release'
      and q."subject_type" = 'drive_node' and q."subject_id" = drive_document_release.node::text
  )) then
    raise exception 'only an approved release request releases a document' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_document_release.node and x."deleted_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if v_node."kind" <> 'file' then
    raise exception 'only a file can be released' using errcode = '22023', hint = 'DRIVE_NOT_A_FILE';
  end if;
  if v_node."document_status" is null or v_node."document_status" not in ('in_review', 'effective') then
    raise exception 'only a document in review or an effective one can be released' using errcode = '22023', hint = 'DRIVE_DOCUMENT_STATUS_INVALID';
  end if;
  select * into v_file from "better_supabase"."attachments" f
  where f."id" = drive_document_release.attachment
    and f."subject_type" = 'drive_node' and f."subject_id" = v_node."id"::text
    and f."uploaded_at" is not null;
  if not found then
    raise exception 'that version of the file was not found' using errcode = 'P0002', hint = 'DRIVE_ATTACHMENT_NOT_FOUND';
  end if;
  select r."id" into v_version from "better_supabase"."versions" r
  where r."subject_type" = 'drive_node' and r."subject_id" = v_node."id"::text
    and r."content" ->> 'attachmentId' = v_file."id"::text
  order by r."number" desc limit 1;
  if v_version is null then
    v_inserted := "better_supabase"."version_insert"(v_node."tenant_id", 'drive_node', v_node."id"::text,
      jsonb_build_object('attachmentId', v_file."id", 'name', v_file."name", 'mimeType', v_file."mime_type", 'size', v_file."size"),
      v_file."bucket" || '/' || v_file."object_path", 'effective', 'manual', true, auth.uid());
    v_version := (v_inserted ->> 'id')::uuid;
  else
    update "better_supabase"."versions" r set "label" = 'effective', "frozen" = true where r."id" = v_version;
  end if;
  update "better_supabase"."versions" r set "label" = 'superseded'
  where r."id" = v_node."effective_version_id" and r."id" <> v_version;
  update "better_supabase"."drive_nodes" x set "effective_version_id" = v_version, "effective_from" = now(),
    "next_review_on" = (current_date + make_interval(months => coalesce(v_node."review_interval_months", 12)))::date, "review_notified_for" = null
  where x."id" = v_node."id";
  if v_node."document_status" = 'in_review' then
    perform "better_supabase"."transition"('drive_node', v_node."id"::text, 'effective', 'released');
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = v_node."id";
  perform "better_supabase".emit_event('drive_node.released', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'documentNumber', v_node."document_number", 'versionId', v_version, 'attachmentId', v_file."id"), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive-files');
  perform better_supabase.audit_event(
    event_type => 'drive_node.released',
    category => 'data',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'document released',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'documentNumber', v_node."document_number", 'versionId', v_version, 'attachmentId', v_file."id")
  );
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_document_review (
  node    uuid,
  outcome text,
  note    text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
begin
  perform better_supabase.raise_actor_readonly() where not better_supabase.actor_may_write();
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_document_review.node and x."deleted_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if v_node."kind" <> 'file' then
    raise exception 'only a file can be reviewed' using errcode = '22023', hint = 'DRIVE_NOT_A_FILE';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_node."document_owner_id" = auth.uid() or "better_supabase"."drive_can"(v_node."id", 'editor')) then
    raise exception 'not allowed to review this document' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if drive_document_review.outcome is null or drive_document_review.outcome not in ('unchanged', 'revise') then
    raise exception 'outcome must be unchanged or revise' using errcode = '22023', hint = 'DRIVE_DOCUMENT_REVIEW_INVALID';
  end if;
  if v_node."document_status" is distinct from 'effective' then
    raise exception 'only an effective document is reviewed' using errcode = '22023', hint = 'DRIVE_DOCUMENT_STATUS_INVALID';
  end if;
  if drive_document_review.outcome = 'unchanged' then
    update "better_supabase"."drive_nodes" x set "next_review_on" = (current_date + make_interval(months => coalesce(v_node."review_interval_months", 12)))::date, "review_notified_for" = null
    where x."id" = v_node."id"
    returning * into v_node;
  end if;
  perform "better_supabase".emit_event('drive_node.reviewed', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'documentNumber', v_node."document_number", 'outcome', drive_document_review.outcome, 'note', drive_document_review.note, 'nextReviewOn', v_node."next_review_on"), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive-files');
  perform better_supabase.audit_event(
    event_type => 'drive_node.reviewed',
    category => 'data',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'document reviewed',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'documentNumber', v_node."document_number", 'outcome', drive_document_review.outcome, 'note', drive_document_review.note, 'nextReviewOn', v_node."next_review_on")
  );
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_document_save (
  node                   uuid,
  document_type          text,
  owner_id               uuid    DEFAULT NULL::uuid,
  review_interval_months integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_seq bigint;
  v_number text;
begin
  perform better_supabase.raise_actor_readonly() where not better_supabase.actor_may_write();
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_document_save.node and x."deleted_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if v_node."kind" <> 'file' then
    raise exception 'only a file can be a controlled document' using errcode = '22023', hint = 'DRIVE_NOT_A_FILE';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'editor')) then
    raise exception 'not allowed to control this document' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (v_node."locked_until" > now() and v_node."locked_by" is distinct from auth.uid() and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'this item is checked out by someone else' using errcode = '55P03', hint = 'DRIVE_LOCKED', detail = jsonb_build_object('lockedBy', v_node."locked_by", 'lockedUntil', v_node."locked_until")::text;
  end if;
  if drive_document_save.document_type is null or not (drive_document_save.document_type = any (array['sop', 'policy', 'form']::text[])) then
    raise exception 'that document type is not in options.control.types' using errcode = '22023', hint = 'DRIVE_DOCUMENT_TYPE_UNKNOWN';
  end if;
  if v_node."document_status" = 'obsolete' then
    raise exception 'an obsolete document can''t change' using errcode = '22023', hint = 'DRIVE_DOCUMENT_STATUS_INVALID';
  end if;
  if drive_document_save.owner_id is not null and not exists (
    select 1 from "public"."memberships" mu
    where mu."organization_id" = v_node."tenant_id" and mu."user_id" = drive_document_save.owner_id
  ) then
    raise exception 'the owner must be a member of the organization' using errcode = '22023', hint = 'DRIVE_DOCUMENT_OWNER_INVALID';
  end if;
  v_number := v_node."document_number";
  if v_number is null then
    v_seq := "better_supabase"."next_number"(v_node."tenant_id", 'drive_document', now());
    v_number := better_supabase.format_assigned_number('DOC-{n:5}', v_seq, now());
  end if;
  update "better_supabase"."drive_nodes" x set "document_number" = v_number,
    "document_type" = drive_document_save.document_type,
    "document_owner_id" = coalesce(drive_document_save.owner_id, x."document_owner_id", auth.uid()),
    "review_interval_months" = coalesce(drive_document_save.review_interval_months, x."review_interval_months"), "updated_at" = now()
  where x."id" = v_node."id"
  returning * into v_node;
  if v_node."document_status" is null then
    perform "better_supabase"."transition"('drive_node', v_node."id"::text, 'draft', null);
    select * into v_node from "better_supabase"."drive_nodes" x where x."id" = v_node."id";
  end if;
  perform "better_supabase".emit_event('drive_node.document_saved', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'documentNumber', v_node."document_number", 'documentType', v_node."document_type", 'ownerId', v_node."document_owner_id"), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive-files');
  perform better_supabase.audit_event(
    event_type => 'drive_node.document_saved',
    category => 'data',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'document saved',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'documentNumber', v_node."document_number", 'documentType', v_node."document_type", 'ownerId', v_node."document_owner_id")
  );
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_document_submit (
  node       uuid,
  attachment uuid DEFAULT NULL::uuid,
  reason     text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_file "better_supabase"."attachments"%rowtype;
  v_revision integer;
  v_request jsonb;
begin
  perform better_supabase.raise_actor_readonly() where not better_supabase.actor_may_write();
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_document_submit.node and x."deleted_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if v_node."kind" <> 'file' then
    raise exception 'only a file can be released' using errcode = '22023', hint = 'DRIVE_NOT_A_FILE';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'editor')) then
    raise exception 'not allowed to submit this document' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (v_node."locked_until" > now() and v_node."locked_by" is distinct from auth.uid() and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'this item is checked out by someone else' using errcode = '55P03', hint = 'DRIVE_LOCKED', detail = jsonb_build_object('lockedBy', v_node."locked_by", 'lockedUntil', v_node."locked_until")::text;
  end if;
  if v_node."document_status" is null then
    raise exception 'save the file as a controlled document first' using errcode = '22023', hint = 'DRIVE_DOCUMENT_STATUS_INVALID';
  end if;
  if not (v_node."document_status" = 'draft' or (v_node."document_status" in ('in_review', 'effective') and not exists (
    select 1 from "better_supabase"."approval_requests" q
    where q."subject_type" = 'drive_node' and q."subject_id" = v_node."id"::text
      and q."action" = 'release' and q."status" = 'pending'
  ))) then
    raise exception 'only a draft, or an effective document without a pending release, can be submitted' using errcode = '22023', hint = 'DRIVE_DOCUMENT_STATUS_INVALID';
  end if;
  select * into v_file from "better_supabase"."attachments" f
  where f."id" = coalesce(drive_document_submit.attachment, v_node."attachment_id")
    and f."subject_type" = 'drive_node' and f."subject_id" = v_node."id"::text
    and f."uploaded_at" is not null;
  if not found then
    raise exception 'that version of the file was not found' using errcode = 'P0002', hint = 'DRIVE_ATTACHMENT_NOT_FOUND';
  end if;
  select r."number" into v_revision from "better_supabase"."versions" r
  where r."subject_type" = 'drive_node' and r."subject_id" = v_node."id"::text
    and r."content" ->> 'attachmentId' = v_file."id"::text
  order by r."number" limit 1;
  if v_node."document_status" = 'draft' then
    perform "better_supabase"."transition"('drive_node', v_node."id"::text, 'in_review', drive_document_submit.reason);
  end if;
  v_request := "better_supabase"."request_approval"(v_node."tenant_id", 'drive_node', v_node."id"::text, 'release',
    drive_document_submit.reason, jsonb_build_object('attachmentId', v_file."id", 'revision', v_revision, 'name', v_file."name"));
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = v_node."id";
  perform "better_supabase".emit_event('drive_node.submitted', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'documentNumber', v_node."document_number", 'attachmentId', v_file."id", 'requestId', v_request ->> 'id'), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive-files');
  perform better_supabase.audit_event(
    event_type => 'drive_node.submitted',
    category => 'data',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'document submitted',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'documentNumber', v_node."document_number", 'attachmentId', v_file."id", 'requestId', v_request ->> 'id')
  );
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_grant_access (
  subject_id text,
  user_id    uuid,
  action     text,
  ends_at    timestamp with time zone
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_role text := case drive_grant_access.action when 'read' then 'viewer' when 'comment' then 'editor' when 'write' then 'editor' end;
begin
  if drive_grant_access.subject_id !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception 'item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_grant_access.subject_id::uuid and x."deleted_at" is null;
  if not found then
    raise exception 'item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if v_role is null then
    raise exception 'action must be read, comment or write' using errcode = '22023', hint = 'DRIVE_ROLE_UNKNOWN';
  end if;
  if drive_grant_access.ends_at is not null and drive_grant_access.ends_at <= now() then
    delete from "better_supabase"."drive_grants" dg where dg."node_id" = v_node."id" and dg."principal_type" = 'user' and dg."principal_id" = drive_grant_access.user_id::text and dg."access_request";
    if found then
      perform "better_supabase".emit_event('drive_node.unshared', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'principalType', 'user', 'principalId', drive_grant_access.user_id::text), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive');
  perform better_supabase.audit_event(
    event_type => 'drive_node.unshared',
    category => 'access',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'access request ended',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'principalType', 'user', 'principalId', drive_grant_access.user_id::text)
  );
    end if;
    return;
  end if;
  if exists (
    select 1 from "better_supabase"."drive_grants" dg
    where dg."node_id" = v_node."id" and dg."principal_type" = 'user' and dg."principal_id" = drive_grant_access.user_id::text and not dg."access_request"
      and coalesce(array_position(array['viewer', 'editor', 'owner']::text[], dg."role"::text), 0) >= coalesce(array_position(array['viewer', 'editor', 'owner']::text[], v_role::text), 0)
      and (dg."expires_at" is null or dg."expires_at" > now())
  ) then
    return;
  end if;
  delete from "better_supabase"."drive_grants" dg where dg."node_id" = v_node."id" and dg."principal_type" = 'user' and dg."principal_id" = drive_grant_access.user_id::text;
  insert into "better_supabase"."drive_grants" ("tenant_id", "node_id", "principal_type", "principal_id", "role", "expires_at", "access_request", "created_by")
  values (v_node."tenant_id", v_node."id", 'user', drive_grant_access.user_id::text, v_role, drive_grant_access.ends_at, true, auth.uid());
  perform "better_supabase".emit_event('drive_node.shared', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'principalType', 'user', 'principalId', drive_grant_access.user_id::text, 'role', v_role), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive');
  perform better_supabase.audit_event(
    event_type => 'drive_node.shared',
    category => 'access',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'access request granted',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'principalType', 'user', 'principalId', drive_grant_access.user_id::text, 'role', v_role)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_hold (
  node  uuid,
  until timestamp with time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_hold.node and x."deleted_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'owner')) then
    raise exception 'not allowed to place a legal hold' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (coalesce(v_node."source"::text, 'internal') not in ('internal', 'request') or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
  if drive_hold.until is null or drive_hold.until <= now() then
    raise exception 'a legal hold needs an end in the future' using errcode = '22023', hint = 'DRIVE_HOLD_INVALID';
  end if;
  update "better_supabase"."drive_nodes" x set "legal_hold_until" = drive_hold.until, "updated_at" = now()
  where x."id" = v_node."id"
  returning * into v_node;
  perform "better_supabase".emit_event('drive_node.hold_placed', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'legalHoldUntil', v_node."legal_hold_until"), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive');
  perform better_supabase.audit_event(
    event_type => 'drive_node.hold_placed',
    category => 'data',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'held',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'legalHoldUntil', v_node."legal_hold_until")
  );
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_insert_node (
  tenant   uuid,
  drive    uuid,
  parent   uuid,
  kind     text,
  name     text,
  conflict text,
  fields   jsonb,
  source   text  DEFAULT 'internal'::text
)
  RETURNS better_supabase.drive_nodes
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_parent "better_supabase"."drive_nodes"%rowtype;
  v_fields "better_supabase"."drive_nodes"%rowtype;
  v_drive uuid := drive_insert_node.drive;
  v_name text;
  v_last text;
begin
  select * into v_parent from "better_supabase"."drive_nodes" x where x."id" = drive_insert_node.parent;
  v_name := "better_supabase"."drive_free_name"(drive_insert_node.tenant, v_drive, drive_insert_node.parent, drive_insert_node.name, null, drive_insert_node.conflict);
  v_fields := jsonb_populate_record(null::"better_supabase"."drive_nodes", coalesce(drive_insert_node.fields, '{}'::jsonb));
  select max(x."rank") into v_last from "better_supabase"."drive_nodes" x
  where x."tenant_id" = drive_insert_node.tenant and x."parent_id" is not distinct from drive_insert_node.parent and x."deleted_at" is null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_drive_node_create"(uuid, uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text, $4::text)', v_hook::oid::regproc)
        using drive_insert_node.tenant, drive_insert_node.parent, drive_insert_node.kind, v_name;
    end if;
  end;
  insert into "better_supabase"."drive_nodes" ("tenant_id", "parent_id", "kind", "name", "rank", "source", "created_by")
  values (drive_insert_node.tenant, drive_insert_node.parent, drive_insert_node.kind, v_name, case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end, drive_insert_node.source, case when drive_insert_node.source = 'request' then null else auth.uid() end)
  returning * into v_node;
  if drive_insert_node.parent is null and auth.uid() is not null then
    insert into "better_supabase"."drive_grants" ("tenant_id", "node_id", "principal_type", "principal_id", "role")
    values (v_node."tenant_id", v_node."id", 'user', auth.uid()::text, 'owner')
    on conflict ("node_id", "principal_type", "principal_id") do update set "role" = excluded."role", "access_request" = false;
  end if;
  perform "better_supabase".emit_event('drive_node.created', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'kind', v_node."kind", 'name', v_node."name", 'parentId', v_node."parent_id", 'source', drive_insert_node.source), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive');
  perform better_supabase.audit_event(
    event_type => 'drive_node.created',
    category => 'data',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'created',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'kind', v_node."kind", 'name', v_node."name", 'parentId', v_node."parent_id", 'source', drive_insert_node.source)
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_drive_node_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_node."id";
    end if;
  end;
  return v_node;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_lock (
  node  uuid,
  until timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  note  text                     DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_until timestamptz := coalesce(drive_lock.until, now() + interval '8 hours');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_lock.node and x."deleted_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if auth.uid() is null then
    raise exception 'not allowed to check out an item without a user' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if not "better_supabase"."drive_node_writable"(v_node."id") then
    if (coalesce(v_node."source"::text, 'internal') not in ('internal', 'request') or false) then
      raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
    end if;
    raise exception 'not allowed to check out this item' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if v_node."kind" <> 'file' then
    raise exception 'only a file can be checked out' using errcode = '22023', hint = 'DRIVE_NOT_A_FILE';
  end if;
  if v_until <= now() or v_until > now() + interval '30 days' then
    raise exception 'a lock ends in the future and within 30 days' using errcode = '22023', hint = 'DRIVE_LOCK_INVALID';
  end if;
  if length(drive_lock.note) > 500 then
    raise exception 'a lock note is at most 500 characters' using errcode = '22023', hint = 'DRIVE_LOCK_INVALID';
  end if;
  if (v_node."locked_until" > now() and v_node."locked_by" is distinct from auth.uid() and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'this item is checked out by someone else' using errcode = '55P03', hint = 'DRIVE_LOCKED', detail = jsonb_build_object('lockedBy', v_node."locked_by", 'lockedUntil', v_node."locked_until")::text;
  end if;
  update "better_supabase"."drive_nodes" x set "locked_by" = auth.uid(), "locked_until" = v_until, "lock_note" = drive_lock.note, "updated_at" = now()
  where x."id" = v_node."id"
  returning * into v_node;
  perform "better_supabase".emit_event('drive_node.locked', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'lockedBy', v_node."locked_by"::text, 'lockedUntil', v_node."locked_until"), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive');
  perform better_supabase.audit_event(
    event_type => 'drive_node.locked',
    category => 'data',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'checked out',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'lockedBy', v_node."locked_by"::text, 'lockedUntil', v_node."locked_until")
  );
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_move (
  node     uuid,
  parent   uuid,
  rank     text DEFAULT NULL::text,
  conflict text DEFAULT NULL::text,
  drive    uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_previous uuid;
  v_target uuid;
  v_name text;
  v_role text;
  v_last text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_move.node and x."deleted_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'editor')) then
    raise exception 'not allowed to move this item' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (coalesce(v_node."source"::text, 'internal') not in ('internal', 'request') or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
  if (v_node."locked_until" > now() and v_node."locked_by" is distinct from auth.uid() and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'this item is checked out by someone else' using errcode = '55P03', hint = 'DRIVE_LOCKED', detail = jsonb_build_object('lockedBy', v_node."locked_by", 'lockedUntil', v_node."locked_until")::text;
  end if;
  if drive_move.rank is not null and drive_move.rank !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'rank must be a key from rankBetween' using errcode = '22023', hint = 'DRIVE_RANK_INVALID';
  end if;
  v_previous := v_node."parent_id";
  if drive_move.parent is null then
    if v_previous is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or ("better_supabase"."drive_can"(v_node."id", 'owner') and coalesce(better_supabase.can('tenant', v_node."tenant_id", 'drive.create'), false))) then
      raise exception 'not allowed to move this item to the top of the drive' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
    end if;
  else
    perform "better_supabase"."drive_check_parent"(v_node."tenant_id", drive_move.parent, drive_move.drive);
    if v_node."id" = any ("better_supabase"."drive_ancestors"(drive_move.parent)) then
      raise exception 'a folder can''t move into itself or its own subfolder' using errcode = '22023', hint = 'DRIVE_MOVE_CYCLE';
    end if;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_drive_node_move"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using v_node."id", drive_move.parent;
    end if;
  end;
  if v_previous is distinct from drive_move.parent then
    v_name := "better_supabase"."drive_free_name"(v_node."tenant_id", v_target, drive_move.parent, v_node."name", v_node."id",
      case when "better_supabase"."drive_conflict"(drive_move.conflict) = 'rename' then 'rename' else 'fail' end);
    if drive_move.parent is null and auth.uid() is not null then
      v_role := "better_supabase"."drive_role"(v_node."id");
      insert into "better_supabase"."drive_grants" ("tenant_id", "node_id", "principal_type", "principal_id", "role")
    values (v_node."tenant_id", v_node."id", 'user', auth.uid()::text, v_role)
    on conflict ("node_id", "principal_type", "principal_id") do update set "role" = excluded."role", "access_request" = false;
    end if;
    if drive_move.rank is null then
      select max(x."rank") into v_last from "better_supabase"."drive_nodes" x
      where x."tenant_id" = v_node."tenant_id" and x."parent_id" is not distinct from drive_move.parent and x."deleted_at" is null;
    end if;
    update "better_supabase"."drive_nodes" x set "parent_id" = drive_move.parent, "name" = v_name, "rank" = coalesce(drive_move.rank, case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end), "updated_at" = now()
    where x."id" = v_node."id"
    returning * into v_node;
    perform "better_supabase".emit_event('drive_node.moved', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'parentId', v_node."parent_id", 'previousParentId', v_previous), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive');
  perform better_supabase.audit_event(
    event_type => 'drive_node.moved',
    category => 'data',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'moved',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'parentId', v_node."parent_id", 'previousParentId', v_previous)
  );
  elsif drive_move.rank is not null then
    update "better_supabase"."drive_nodes" x set "rank" = drive_move.rank, "updated_at" = now()
    where x."id" = v_node."id"
    returning * into v_node;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_drive_node_move"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_node."id";
    end if;
  end;
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_node_purging()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_objects jsonb := (select coalesce(jsonb_agg(jsonb_build_object('bucket', pa."bucket", 'path', pa."object_path")), '[]'::jsonb) from "better_supabase"."attachments" pa where pa."subject_type" = 'drive_node' and pa."subject_id" = old."id"::text and pa."uploaded_at" is not null);
begin
  perform "better_supabase".emit_event('drive_node.purged', jsonb_build_object('organizationId', old."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', old."id"::text, 'objects', v_objects), 'drive-nodes/' || old."id"::text, (old."tenant_id")::text, null, 'better-supabase/drive-files');
  perform better_supabase.audit_event(
    event_type => 'drive_node.purged',
    category => 'data',
    target_type => 'drive_node',
    record_id => old."id"::text,
    target_label => old."name",
    summary => 'deleted for good',
    tenant => (old."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', old."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', old."id"::text, 'objects', v_objects)
  );
  return old;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_release_hold (
  node uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_release_hold.node and x."deleted_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'owner')) then
    raise exception 'not allowed to release a legal hold' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (coalesce(v_node."source"::text, 'internal') not in ('internal', 'request') or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
  update "better_supabase"."drive_nodes" x set "legal_hold_until" = null, "updated_at" = now()
  where x."id" = v_node."id"
  returning * into v_node;
  perform "better_supabase".emit_event('drive_node.hold_released', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive');
  perform better_supabase.audit_event(
    event_type => 'drive_node.hold_released',
    category => 'data',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'released',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text)
  );
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_rename (
  node     uuid,
  name     text,
  conflict text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_previous text;
  v_name text := "better_supabase"."drive_clean_name"(drive_rename.name);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_rename.node and x."deleted_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'editor')) then
    raise exception 'not allowed to rename this item' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (coalesce(v_node."source"::text, 'internal') not in ('internal', 'request') or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
  if (v_node."locked_until" > now() and v_node."locked_by" is distinct from auth.uid() and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'this item is checked out by someone else' using errcode = '55P03', hint = 'DRIVE_LOCKED', detail = jsonb_build_object('lockedBy', v_node."locked_by", 'lockedUntil', v_node."locked_until")::text;
  end if;
  if v_name = v_node."name" then
    return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
  end if;
  v_name := "better_supabase"."drive_free_name"(v_node."tenant_id", null, v_node."parent_id", v_name, v_node."id",
    case when "better_supabase"."drive_conflict"(drive_rename.conflict) = 'rename' then 'rename' else 'fail' end);
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_drive_node_rename"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_node."id", v_name;
    end if;
  end;
  v_previous := v_node."name";
  update "better_supabase"."drive_nodes" x set "name" = v_name, "updated_at" = now()
  where x."id" = v_node."id"
  returning * into v_node;
  perform "better_supabase".emit_event('drive_node.renamed', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'name', v_node."name", 'previousName', v_previous), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive');
  perform better_supabase.audit_event(
    event_type => 'drive_node.renamed',
    category => 'data',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'renamed',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'name', v_node."name", 'previousName', v_previous)
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_drive_node_rename"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_node."id";
    end if;
  end;
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_set_download_blocked (
  target_type text,
  target_id   uuid,
  blocked     boolean
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if drive_set_download_blocked.target_type is null or drive_set_download_blocked.target_type not in ('node') then
    raise exception 'target_type must be node' using errcode = '22023', hint = 'DRIVE_TARGET_INVALID';
  end if;
  if drive_set_download_blocked.blocked is null then
    raise exception 'blocked must be true or false' using errcode = '22023', hint = 'DRIVE_TARGET_INVALID';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_set_download_blocked.target_id and x."deleted_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'owner')) then
    raise exception 'not allowed to change downloads of this item' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (coalesce(v_node."source"::text, 'internal') not in ('internal', 'request') or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
  if v_node."download_blocked" is distinct from drive_set_download_blocked.blocked then
    update "better_supabase"."drive_nodes" x set "download_blocked" = drive_set_download_blocked.blocked, "updated_at" = now()
    where x."id" = v_node."id"
    returning * into v_node;
    perform "better_supabase".emit_event('drive_node.download_blocked_changed', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'downloadBlocked', v_node."download_blocked"), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive');
  perform better_supabase.audit_event(
    event_type => 'drive_node.download_blocked_changed',
    category => 'access',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'download block changed',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'downloadBlocked', v_node."download_blocked")
  );
  end if;
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_share (
  node           uuid,
  principal_type text,
  principal_id   text,
  role           text,
  expires_at     timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_type text := lower(drive_share.principal_type);
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_share.node and x."deleted_at" is null;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or ("better_supabase"."drive_can"(v_node."id", 'owner') and coalesce(array_position(array['viewer', 'editor', 'owner']::text[], drive_share.role::text), 0) <= coalesce(array_position(array['viewer', 'editor', 'owner']::text[], "better_supabase"."drive_role"(v_node."id")::text), 0))) then
    raise exception 'not allowed to share this item with that role' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (coalesce(v_node."source"::text, 'internal') not in ('internal', 'request') or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
  if coalesce(array_position(array['viewer', 'editor', 'owner']::text[], drive_share.role::text), 0) = 0 and drive_share.role is distinct from 'contributor' then
    raise exception 'role must be one of viewer, editor, owner, contributor' using errcode = '22023', hint = 'DRIVE_ROLE_UNKNOWN';
  end if;
  if drive_share.role = 'contributor' and v_node."kind" <> 'folder' then
    raise exception 'the upload role is for folders' using errcode = '22023', hint = 'DRIVE_ROLE_UNKNOWN', detail = '{"reason":"upload role is for folders"}';
  end if;
  if v_type not in ('user', 'team', 'role') or drive_share.principal_id is null then
    raise exception 'principal_type must be user, team or role' using errcode = '22023', hint = 'DRIVE_PRINCIPAL_INVALID';
  end if;
  if (v_type = 'user' and (drive_share.principal_id !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' or not exists (
      select 1 from "public"."memberships" mu
      where mu."organization_id" = v_node."tenant_id" and mu."user_id" = drive_share.principal_id::uuid
    )))
    or (v_type = 'team' and not exists (select 1 from "better_supabase"."teams" t where t."id"::text = drive_share.principal_id and t."tenant_id" = v_node."tenant_id")) then
    raise exception 'no member or team of this organization has that id' using errcode = 'P0002', hint = 'DRIVE_PRINCIPAL_NOT_FOUND';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_drive_node_share"(uuid, text, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::text)', v_hook::oid::regproc)
        using v_node."id", v_type, drive_share.principal_id, drive_share.role;
    end if;
  end;
  delete from "better_supabase"."drive_grants" dg where dg."node_id" = v_node."id" and dg."principal_type" = v_type and dg."principal_id" = drive_share.principal_id;
  insert into "better_supabase"."drive_grants" ("tenant_id", "node_id", "principal_type", "principal_id", "role", "expires_at", "created_by")
  values (v_node."tenant_id", v_node."id", v_type, drive_share.principal_id, drive_share.role, drive_share.expires_at, auth.uid())
  returning "id" into v_id;
  perform "better_supabase".emit_event('drive_node.shared', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'principalType', v_type, 'principalId', drive_share.principal_id, 'role', drive_share.role), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive');
  perform better_supabase.audit_event(
    event_type => 'drive_node.shared',
    category => 'access',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'shared',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'principalType', v_type, 'principalId', drive_share.principal_id, 'role', drive_share.role)
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_drive_node_share"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using v_node."id", v_id;
    end if;
  end;
  return jsonb_build_object('id', v_id, 'nodeId', v_node."id", 'principalType', v_type, 'principalId', drive_share.principal_id, 'role', drive_share.role, 'expiresAt', drive_share.expires_at, 'inherited', false);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_transfer_ownership (
  tenant    uuid,
  from_user uuid,
  to_user   uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_grant "better_supabase"."drive_grants"%rowtype;
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_drive_ids uuid[] := '{}';
  v_nodes integer := 0;
  v_drives integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', drive_transfer_ownership.tenant, 'drive.manage'), false)) then
    raise exception 'you can''t transfer items in this organization' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if drive_transfer_ownership.from_user is null or drive_transfer_ownership.to_user is null
    or drive_transfer_ownership.from_user = drive_transfer_ownership.to_user then
    raise exception 'name two different users to transfer between' using errcode = '22023', hint = 'DRIVE_TRANSFER_INVALID';
  end if;
  if not exists (
    select 1 from "public"."memberships" mu
    where mu."organization_id" = drive_transfer_ownership.tenant and mu."user_id" = drive_transfer_ownership.to_user
  ) then
    raise exception 'the new owner is not an active member of this organization' using errcode = 'P0002', hint = 'DRIVE_PRINCIPAL_NOT_FOUND';
  end if;
  for v_grant in
    select gr.* from "better_supabase"."drive_grants" gr
    where gr."tenant_id" = drive_transfer_ownership.tenant and gr."role"::text = 'owner'
      and gr."principal_type" = 'user' and gr."principal_id" = drive_transfer_ownership.from_user::text
  loop
    delete from "better_supabase"."drive_grants" gr where gr."node_id" = v_grant."node_id" and gr."principal_type" = 'user' and gr."principal_id" = drive_transfer_ownership.to_user::text;
    update "better_supabase"."drive_grants" set "principal_id" = drive_transfer_ownership.to_user::text where "id" = v_grant."id";
    select * into v_node from "better_supabase"."drive_nodes" x where x."id" = v_grant."node_id";
    v_nodes := v_nodes + 1;
    perform "better_supabase".emit_event('drive_node.ownership_transferred', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'fromUserId', drive_transfer_ownership.from_user::text, 'toUserId', drive_transfer_ownership.to_user::text), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive');
  perform better_supabase.audit_event(
    event_type => 'drive_node.ownership_transferred',
    category => 'access',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'ownership transferred',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'fromUserId', drive_transfer_ownership.from_user::text, 'toUserId', drive_transfer_ownership.to_user::text)
  );
  end loop;
  return jsonb_build_object('nodes', v_nodes, 'drives', v_drives);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_unlock (
  node  uuid,
  force boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_holder uuid;
  v_forced boolean := false;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_unlock.node and x."deleted_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if v_node."locked_until" is null or v_node."locked_until" <= now() then
    if v_node."locked_by" is not null then
      update "better_supabase"."drive_nodes" x set "locked_by" = null, "locked_until" = null, "lock_note" = null
      where x."id" = v_node."id"
      returning * into v_node;
    end if;
    return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
  end if;
  v_holder := v_node."locked_by";
  if v_holder is distinct from auth.uid() and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    if not coalesce(drive_unlock.force, false) then
      raise exception 'this item is checked out by someone else' using errcode = '55P03', hint = 'DRIVE_LOCKED', detail = jsonb_build_object('lockedBy', v_node."locked_by", 'lockedUntil', v_node."locked_until")::text;
    end if;
    if not "better_supabase"."drive_can"(v_node."id", 'owner') then
      raise exception 'not allowed to break someone else''s lock' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
    end if;
    v_forced := true;
  end if;
  update "better_supabase"."drive_nodes" x set "locked_by" = null, "locked_until" = null, "lock_note" = null, "updated_at" = now()
  where x."id" = v_node."id"
  returning * into v_node;
  perform "better_supabase".emit_event('drive_node.unlocked', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'lockedBy', v_holder::text, 'forced', v_forced), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive');
  perform better_supabase.audit_event(
    event_type => 'drive_node.unlocked',
    category => 'data',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'checked in',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'lockedBy', v_holder::text, 'forced', v_forced)
  );
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_unshare (
  node           uuid,
  principal_type text,
  principal_id   text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_type text := lower(drive_unshare.principal_type);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_unshare.node and x."deleted_at" is null;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'owner')) then
    raise exception 'not allowed to change who this item is shared with' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (coalesce(v_node."source"::text, 'internal') not in ('internal', 'request') or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
  delete from "better_supabase"."drive_grants" dg where dg."node_id" = v_node."id"
    and dg."principal_type" = v_type and dg."principal_id" = drive_unshare.principal_id;
  if not found then
    return false;
  end if;
  perform "better_supabase".emit_event('drive_node.unshared', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'principalType', v_type, 'principalId', drive_unshare.principal_id), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive');
  perform better_supabase.audit_event(
    event_type => 'drive_node.unshared',
    category => 'access',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'unshared',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'principalType', v_type, 'principalId', drive_unshare.principal_id)
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.end_access (
  request_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  SET "IntervalStyle" TO 'iso_8601'
  AS $function$
declare
  v_row "better_supabase"."access_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."access_requests" r where r."id" = end_access.request_id for update;
  if not found then
    raise exception 'access request not found' using errcode = 'P0002', hint = 'ACCESS_REQUEST_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."user_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'access_requests.manage'), false)) then
    raise exception 'not allowed to end this access' using errcode = '42501', hint = 'ACCESS_REQUEST_FORBIDDEN';
  end if;
  if v_row."granted_at" is null or v_row."ended_at" is not null then
    raise exception 'this access isn''t active' using errcode = '22023', hint = 'ACCESS_NOT_GRANTED';
  end if;
  if v_row."target" = 'record' then
    case v_row."subject_type"
    when 'drive_node' then
      perform "better_supabase"."drive_grant_access"(v_row."subject_id", v_row."user_id", v_row."action", now());
    else
      if v_row."member_id" is not null then
        perform "better_supabase"."close_subject_member"(v_row."member_id");
      end if;
    end case;
  else
    -- Only a role that is still the granted one goes back; a later change wins.
    if exists (
      select 1 from "public"."memberships" m
      where m."organization_id" = v_row."tenant_id" and m."user_id" = v_row."user_id"
        and (select r."key" from "better_supabase"."roles" r where r."id" = m."role") = v_row."role"
    ) then
      if v_row."previous_role" is null then
        delete from "public"."memberships" where "organization_id" = v_row."tenant_id" and "user_id" = v_row."user_id";
      else
        update "public"."memberships" set "role" = (select r."id" from "better_supabase"."roles" r where (r."id"::text = (v_row."previous_role")::text or r."key" = (v_row."previous_role")::text) order by (r."id"::text = (v_row."previous_role")::text) desc limit 1)
        where "organization_id" = v_row."tenant_id" and "user_id" = v_row."user_id";
      end if;
    end if;
  end if;
  update "better_supabase"."access_requests" r set "ended_at" = now() where r."id" = v_row."id" returning * into v_row;
  perform "better_supabase".emit_event('access_request.ended', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'userId', v_row."user_id", 'role', v_row."role", 'id', v_row."id", 'approvalId', v_row."approval_id", 'expiresAt', v_row."expires_at", 'target', v_row."target", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'action', v_row."action", 'reason', 'revoked'), 'access-requests/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/access-requests');
  perform better_supabase.audit_event(
    event_type => 'access_request.ended',
    category => 'membership',
    target_type => 'user',
    record_id => v_row."user_id"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'userId', v_row."user_id", 'role', v_row."role", 'id', v_row."id", 'approvalId', v_row."approval_id", 'expiresAt', v_row."expires_at", 'target', v_row."target", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'action', v_row."action", 'reason', 'revoked')
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'role', v_row."role", 'target', v_row."target", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'action', v_row."action", 'emergency', v_row."emergency", 'review', case when v_row."reviewed_at" is null then null else jsonb_build_object('verdict', v_row."review_verdict", 'note', v_row."review_note", 'reviewedBy', v_row."reviewed_by", 'reviewedAt', v_row."reviewed_at") end, 'previousRole', v_row."previous_role", 'reason', v_row."reason", 'duration', v_row."duration"::text, 'status', 'ended', 'approvalId', v_row."approval_id", 'grantedAt', v_row."granted_at", 'expiresAt', v_row."expires_at", 'endedAt', v_row."ended_at", 'createdAt', v_row."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.expire_access_grants (
  max_grants integer DEFAULT 200
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."access_requests"%rowtype;
  v_count integer := 0;
begin
  for v_row in
    select * from "better_supabase"."access_requests" r
    where r."granted_at" is not null and r."ended_at" is null and r."expires_at" <= now()
    order by r."expires_at"
    limit greatest(coalesce(expire_access_grants.max_grants, 200), 1)
    for update skip locked
  loop
    if v_row."target" = 'role' then
      -- Only a role that is still the granted one goes back; a later change wins.
      if exists (
        select 1 from "public"."memberships" m
        where m."organization_id" = v_row."tenant_id" and m."user_id" = v_row."user_id"
          and (select r."key" from "better_supabase"."roles" r where r."id" = m."role") = v_row."role"
      ) then
        if v_row."previous_role" is null then
          delete from "public"."memberships" where "organization_id" = v_row."tenant_id" and "user_id" = v_row."user_id";
        else
          update "public"."memberships" set "role" = (select r."id" from "better_supabase"."roles" r where (r."id"::text = (v_row."previous_role")::text or r."key" = (v_row."previous_role")::text) order by (r."id"::text = (v_row."previous_role")::text) desc limit 1)
          where "organization_id" = v_row."tenant_id" and "user_id" = v_row."user_id";
        end if;
      end if;
    end if;
    update "better_supabase"."access_requests" r set "ended_at" = now() where r."id" = v_row."id" returning * into v_row;
    perform "better_supabase".emit_event('access_request.ended', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'userId', v_row."user_id", 'role', v_row."role", 'id', v_row."id", 'approvalId', v_row."approval_id", 'expiresAt', v_row."expires_at", 'target', v_row."target", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'action', v_row."action", 'reason', 'expired'), 'access-requests/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/access-requests');
  perform better_supabase.audit_event(
    event_type => 'access_request.ended',
    category => 'membership',
    target_type => 'user',
    record_id => v_row."user_id"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'userId', v_row."user_id", 'role', v_row."role", 'id', v_row."id", 'approvalId', v_row."approval_id", 'expiresAt', v_row."expires_at", 'target', v_row."target", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'action', v_row."action", 'reason', 'expired')
  );
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.grant_access_request (
  request_id uuid
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."access_requests"%rowtype;
  v_previous text;
  v_ends timestamptz;
  v_member uuid;
begin
  select * into v_row from "better_supabase"."access_requests" r where r."id" = grant_access_request.request_id for update;
  if not found or v_row."granted_at" is not null then
    return;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_access_grant"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  if v_row."target" = 'record' then
    v_ends := now() + v_row."duration";
    case v_row."subject_type"
    when 'drive_node' then
      perform "better_supabase"."drive_grant_access"(v_row."subject_id", v_row."user_id", v_row."action", v_ends);
    else
      v_member := "better_supabase"."grant_subject_member"(v_row."subject_type", v_row."subject_id", v_row."user_id", v_ends, v_row."emergency", v_row."reason");
    end case;
    update "better_supabase"."access_requests" r
    set "granted_at" = now(), "expires_at" = v_ends, "member_id" = v_member
    where r."id" = v_row."id"
    returning * into v_row;
    if not v_row."emergency" then
      perform "better_supabase".emit_event('access_request.approved', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'userId', v_row."user_id", 'role', v_row."role", 'id', v_row."id", 'approvalId', v_row."approval_id", 'expiresAt', v_row."expires_at", 'target', v_row."target", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'action', v_row."action"), 'access-requests/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/access-requests');
  perform better_supabase.audit_event(
    event_type => 'access_request.approved',
    category => 'membership',
    target_type => 'user',
    record_id => v_row."user_id"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'userId', v_row."user_id", 'role', v_row."role", 'id', v_row."id", 'approvalId', v_row."approval_id", 'expiresAt', v_row."expires_at", 'target', v_row."target", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'action', v_row."action")
  );
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_access_grant"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
    return;
  end if;
  select (select r."key" from "better_supabase"."roles" r where r."id" = m."role") into v_previous from "public"."memberships" m
  where m."organization_id" = v_row."tenant_id" and m."user_id" = v_row."user_id"
  for update;
  if found then
    update "public"."memberships" set "role" = (select r."id" from "better_supabase"."roles" r where (r."id"::text = (v_row."role")::text or r."key" = (v_row."role")::text) order by (r."id"::text = (v_row."role")::text) desc limit 1)
    where "organization_id" = v_row."tenant_id" and "user_id" = v_row."user_id";
  else
    insert into "public"."memberships" ("organization_id", "user_id", "role")
    values (v_row."tenant_id", v_row."user_id", (select r."id" from "better_supabase"."roles" r where (r."id"::text = (v_row."role")::text or r."key" = (v_row."role")::text) order by (r."id"::text = (v_row."role")::text) desc limit 1));
  end if;
  update "better_supabase"."access_requests" r
  set "previous_role" = v_previous,
      "granted_at" = now(),
      "expires_at" = case when v_row."duration" is null then null else now() + v_row."duration" end
  where r."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('access_request.approved', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'userId', v_row."user_id", 'role', v_row."role", 'id', v_row."id", 'approvalId', v_row."approval_id", 'expiresAt', v_row."expires_at", 'target', v_row."target", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'action', v_row."action"), 'access-requests/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/access-requests');
  perform better_supabase.audit_event(
    event_type => 'access_request.approved',
    category => 'membership',
    target_type => 'user',
    record_id => v_row."user_id"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'userId', v_row."user_id", 'role', v_row."role", 'id', v_row."id", 'approvalId', v_row."approval_id", 'expiresAt', v_row."expires_at", 'target', v_row."target", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'action', v_row."action")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_access_grant"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.invoice_from_time (
  tenant   uuid,
  attrs    jsonb,
  scope    jsonb DEFAULT NULL::jsonb,
  group_by text  DEFAULT 'subject'::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_scope jsonb := coalesce(invoice_from_time.scope, '{}'::jsonb);
  v_currency text := upper(invoice_from_time.attrs ->> 'currency');
  v_currencies text[];
  v_unrated integer;
  v_lines jsonb;
  v_entries jsonb;
  v_total bigint;
  v_invoice jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', invoice_from_time.tenant, 'billable_time.invoice'), false)) then
    raise exception 'not allowed to invoice time' using errcode = '42501', hint = 'BILLABLE_TIME_FORBIDDEN';
  end if;
  if invoice_from_time.group_by not in ('subject', 'member', 'entry') then
    raise exception 'group_by is subject, member or entry' using errcode = '22023', hint = 'BILLABLE_TIME_GROUPING_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('billable_time:' || invoice_from_time.tenant::text, 0));
  select count(*) filter (where u.rate is null), array_agg(distinct u.currency) filter (where u.rate is not null)
    into v_unrated, v_currencies
  from (
    select x."id" as id, x."user_id" as user_id, x."subject_type" as subject_type, x."subject_id" as subject_id,
      x."started_at" as started_at, x."note" as note, extract(epoch from x."ended_at" - x."started_at") as seconds,
      coalesce(x."rate", card.rate) as rate, coalesce(x."rate_currency", card.currency) as currency
    from "better_supabase"."time_entries" x
    left join lateral (
      select c."rate" as rate, c."currency"::text as currency
      from "better_supabase"."time_rates" c
      where c."tenant_id" = x."tenant_id"
        and (c."user_id" is null or c."user_id" = x."user_id")
        and (c."subject_type" is null or (c."subject_type" = x."subject_type" and c."subject_id" = x."subject_id"))
        and c."effective_from" <= (x."started_at" at time zone 'UTC')::date
      order by (c."subject_type" is not null) desc, (c."user_id" is not null) desc, c."effective_from" desc
      limit 1
    ) card on x."rate" is null
    where x."tenant_id" = invoice_from_time.tenant
      and x."billable" and x."ended_at" is not null
      and not exists (select 1 from "better_supabase"."time_invoice_entries" d where d."entry_id" = x."id")
      and (v_scope -> 'subject' is null or (x."subject_type" = v_scope -> 'subject' ->> 'type' and x."subject_id" = v_scope -> 'subject' ->> 'id'))
      and (v_scope ->> 'userId' is null or x."user_id" = (v_scope ->> 'userId')::uuid)
      and (v_scope ->> 'starts' is null or x."started_at" >= (v_scope ->> 'starts')::timestamptz)
      and (v_scope ->> 'ends' is null or x."started_at" < (v_scope ->> 'ends')::timestamptz)
      and (v_scope -> 'entryIds' is null or x."id"::text in (select jsonb_array_elements_text(v_scope -> 'entryIds')))) u;
  if v_unrated > 0 then
    raise exception 'some billable entries have no rate; set one on the entry or the rate card' using errcode = '22023', hint = 'TIME_RATE_MISSING';
  end if;
  if v_currency is null then
    if coalesce(array_length(v_currencies, 1), 0) > 1 then
      raise exception 'the entries are billed in several currencies; name one' using errcode = '22023', hint = 'BILLABLE_TIME_CURRENCIES';
    end if;
    v_currency := v_currencies[1];
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('description', l.description, 'quantity', l.quantity, 'unitAmount', l.rate::text) order by l.first_at), '[]'::jsonb),
    coalesce(jsonb_agg(l.entry_ids), '[]'::jsonb),
    coalesce(sum(round(l.quantity * l.rate)), 0)::bigint
    into v_lines, v_entries, v_total
  from (
    select min(u.started_at) as first_at, u.currency, u.rate,
      round(sum(u.seconds) / 3600.0, 4) as quantity,
      jsonb_agg(u.id order by u.started_at, u.id) as entry_ids,
      case when invoice_from_time.group_by = 'entry' then min(u.user_id::text) end as user_text,
      case when invoice_from_time.group_by = 'member' then min(u.user_id::text) end as member_text,
      min(u.subject_type) as subject_type, min(u.subject_id) as subject_id,
      case
        when invoice_from_time.group_by = 'entry' then coalesce(min(u.note), 'Time on ' || to_char(min(u.started_at) at time zone 'UTC', 'YYYY-MM-DD'))
        when min(u.subject_type) is null then 'Time'
        else 'Time on ' || min(u.subject_type) || ' ' || min(u.subject_id)
      end as description
    from (
    select x."id" as id, x."user_id" as user_id, x."subject_type" as subject_type, x."subject_id" as subject_id,
      x."started_at" as started_at, x."note" as note, extract(epoch from x."ended_at" - x."started_at") as seconds,
      coalesce(x."rate", card.rate) as rate, coalesce(x."rate_currency", card.currency) as currency
    from "better_supabase"."time_entries" x
    left join lateral (
      select c."rate" as rate, c."currency"::text as currency
      from "better_supabase"."time_rates" c
      where c."tenant_id" = x."tenant_id"
        and (c."user_id" is null or c."user_id" = x."user_id")
        and (c."subject_type" is null or (c."subject_type" = x."subject_type" and c."subject_id" = x."subject_id"))
        and c."effective_from" <= (x."started_at" at time zone 'UTC')::date
      order by (c."subject_type" is not null) desc, (c."user_id" is not null) desc, c."effective_from" desc
      limit 1
    ) card on x."rate" is null
    where x."tenant_id" = invoice_from_time.tenant
      and x."billable" and x."ended_at" is not null
      and not exists (select 1 from "better_supabase"."time_invoice_entries" d where d."entry_id" = x."id")
      and (v_scope -> 'subject' is null or (x."subject_type" = v_scope -> 'subject' ->> 'type' and x."subject_id" = v_scope -> 'subject' ->> 'id'))
      and (v_scope ->> 'userId' is null or x."user_id" = (v_scope ->> 'userId')::uuid)
      and (v_scope ->> 'starts' is null or x."started_at" >= (v_scope ->> 'starts')::timestamptz)
      and (v_scope ->> 'ends' is null or x."started_at" < (v_scope ->> 'ends')::timestamptz)
      and (v_scope -> 'entryIds' is null or x."id"::text in (select jsonb_array_elements_text(v_scope -> 'entryIds')))) u
    where u.rate is not null
    group by u.currency, u.rate, u.subject_type, u.subject_id,
      case when invoice_from_time.group_by in ('member', 'entry') then u.user_id end,
      case when invoice_from_time.group_by = 'entry' then u.id end
    having round(sum(u.seconds) / 3600.0, 4) > 0) l
  where l.currency = v_currency;
  if jsonb_array_length(v_lines) = 0 then
    raise exception 'no unbilled billable time matches' using errcode = 'P0002', hint = 'BILLABLE_TIME_EMPTY';
  end if;
  select coalesce(jsonb_agg(x.value order by x.value), '[]'::jsonb) into v_entries
  from jsonb_array_elements(v_entries) g, jsonb_array_elements(g.value) x;
  v_invoice := "better_supabase"."create_invoice"(invoice_from_time.tenant,
    (coalesce(invoice_from_time.attrs, '{}'::jsonb) - 'origin') || jsonb_build_object('currency', v_currency,
      'title', coalesce(nullif(trim(invoice_from_time.attrs ->> 'title'), ''), 'Time')), v_lines);
  insert into "better_supabase"."time_invoice_entries" ("entry_id", "tenant_id", "invoice_id", "rate", "currency", "seconds")
  select u.id, invoice_from_time.tenant, (v_invoice ->> 'id')::uuid, u.rate, u.currency, round(u.seconds)::bigint
  from (
    select x."id" as id, x."user_id" as user_id, x."subject_type" as subject_type, x."subject_id" as subject_id,
      x."started_at" as started_at, x."note" as note, extract(epoch from x."ended_at" - x."started_at") as seconds,
      coalesce(x."rate", card.rate) as rate, coalesce(x."rate_currency", card.currency) as currency
    from "better_supabase"."time_entries" x
    left join lateral (
      select c."rate" as rate, c."currency"::text as currency
      from "better_supabase"."time_rates" c
      where c."tenant_id" = x."tenant_id"
        and (c."user_id" is null or c."user_id" = x."user_id")
        and (c."subject_type" is null or (c."subject_type" = x."subject_type" and c."subject_id" = x."subject_id"))
        and c."effective_from" <= (x."started_at" at time zone 'UTC')::date
      order by (c."subject_type" is not null) desc, (c."user_id" is not null) desc, c."effective_from" desc
      limit 1
    ) card on x."rate" is null
    where x."tenant_id" = invoice_from_time.tenant
      and x."billable" and x."ended_at" is not null
      and not exists (select 1 from "better_supabase"."time_invoice_entries" d where d."entry_id" = x."id")
      and (v_scope -> 'subject' is null or (x."subject_type" = v_scope -> 'subject' ->> 'type' and x."subject_id" = v_scope -> 'subject' ->> 'id'))
      and (v_scope ->> 'userId' is null or x."user_id" = (v_scope ->> 'userId')::uuid)
      and (v_scope ->> 'starts' is null or x."started_at" >= (v_scope ->> 'starts')::timestamptz)
      and (v_scope ->> 'ends' is null or x."started_at" < (v_scope ->> 'ends')::timestamptz)
      and (v_scope -> 'entryIds' is null or x."id"::text in (select jsonb_array_elements_text(v_scope -> 'entryIds')))) u
  where u.id::text in (select jsonb_array_elements_text(v_entries));
  perform "better_supabase".emit_event('time_entry.invoiced', jsonb_build_object('organizationId', invoice_from_time.tenant, 'invoiceId', v_invoice ->> 'id', 'entryIds', v_entries, 'currency', v_currency, 'total', v_total::text), 'invoices/' || (v_invoice ->> 'id'), (invoice_from_time.tenant::text)::text, null, 'better-supabase/billable-time');
  perform better_supabase.audit_event(
    event_type => 'time_entry.invoiced',
    category => 'billing',
    target_type => 'invoice',
    record_id => v_invoice ->> 'id',
    summary => 'invoiced time',
    tenant => (invoice_from_time.tenant::text)::uuid,
    metadata => jsonb_build_object('organizationId', invoice_from_time.tenant, 'invoiceId', v_invoice ->> 'id', 'entryIds', v_entries, 'currency', v_currency, 'total', v_total::text)
  );
  return jsonb_build_object('invoiceId', v_invoice ->> 'id', 'currency', v_currency, 'total', v_total::text, 'entryIds', v_entries);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.log_activity (
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
  v_tenant uuid := log_activity.tenant;
  v_type text := log_activity.attrs ->> 'type';
  v_title text := nullif(trim(log_activity.attrs ->> 'title'), '');
  v_owner uuid := coalesce(nullif(log_activity.attrs ->> 'ownerId', '')::uuid, auth.uid());
  v_previous_owner uuid;
  v_item jsonb;
  v_subjects jsonb;
  v_first jsonb;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'activities.write'), false)) then
    raise exception 'not allowed to log engagements' using errcode = '42501', hint = 'ACTIVITY_FORBIDDEN';
  end if;
  if v_type is null or not (v_type = any ('{call,email,meeting,note,task}'::text[])) then
    raise exception 'unknown engagement type' using errcode = '22023', hint = 'ACTIVITY_TYPE_INVALID';
  end if;
  if v_title is null then
    raise exception 'a title is required' using errcode = '23502', hint = 'ACTIVITY_TITLE_REQUIRED';
  end if;
  if nullif(log_activity.attrs ->> 'audience', '') is not null and not (log_activity.attrs ->> 'audience' = any ('{team,subject,restricted}'::text[])) then
    raise exception 'audience must be one of team, subject, restricted' using errcode = '22023', hint = 'ACTIVITY_AUDIENCE_INVALID';
  end if;
  if log_activity.attrs ? 'restrictedRoles' and jsonb_typeof(log_activity.attrs -> 'restrictedRoles') not in ('array', 'null') then
    raise exception 'restrictedRoles must be a list of record team roles' using errcode = '22023', hint = 'ACTIVITY_AUDIENCE_INVALID';
  end if;
  if nullif(log_activity.attrs ->> 'category', '') is not null and not (log_activity.attrs ->> 'category' = any ('{general,care,medical,behavior,family,incident}'::text[])) then
    raise exception 'category must be one of general, care, medical, behavior, family, incident' using errcode = '22023', hint = 'ACTIVITY_CATEGORY_INVALID';
  end if;
  if exists (select 1 from "better_supabase"."engagements" x where x."tenant_id" = v_tenant and x."external_ref" = log_activity.attrs ->> 'externalRef' and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the engagement is locked: add an addendum with amend_activity instead' using errcode = '55000', hint = 'ACTIVITY_LOCKED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_activity_log"(uuid, jsonb, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb, $3::jsonb)', v_hook::oid::regproc)
        using log_activity.tenant, log_activity.attrs, log_activity.subjects;
    end if;
  end;
  insert into "better_supabase"."engagements" ("tenant_id", "type", "title", "body", "outcome", "owner_user_id", "due_at", "done_at", "duration_seconds", "external_ref", "created_by", "audience", "restricted_roles", "category", "locked_at", "goal_id")
  values (v_tenant, v_type, v_title, log_activity.attrs ->> 'body', log_activity.attrs ->> 'outcome', v_owner, (log_activity.attrs ->> 'dueAt')::timestamptz, (log_activity.attrs ->> 'doneAt')::timestamptz, (log_activity.attrs ->> 'durationSeconds')::integer, log_activity.attrs ->> 'externalRef', auth.uid(), coalesce(nullif(log_activity.attrs ->> 'audience', ''), 'team'), nullif((select coalesce(array_agg(r.value order by r.ordinality), '{}'::text[]) from jsonb_array_elements_text(case when jsonb_typeof(log_activity.attrs -> 'restrictedRoles') = 'array' then log_activity.attrs -> 'restrictedRoles' else '[]'::jsonb end) with ordinality r), '{}'), nullif(log_activity.attrs ->> 'category', ''), case when v_type = any ('{note,report}'::text[]) then now() + interval '24 hours' end, nullif(log_activity.attrs ->> 'goalId', '')::uuid)
  on conflict ("tenant_id", "external_ref") where "external_ref" is not null do update set
    "title" = excluded."title", "body" = excluded."body", "outcome" = excluded."outcome",
    "due_at" = excluded."due_at", "done_at" = excluded."done_at", "duration_seconds" = excluded."duration_seconds", "updated_at" = now()
  returning "id" into v_id;
  
  if jsonb_typeof(coalesce(log_activity.subjects, '[]')) <> 'array' then
    raise exception 'subjects must be a list of { type, id }' using errcode = '22023', hint = 'ACTIVITY_SUBJECTS_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(log_activity.subjects, '[]')) loop
    if not (case (v_item ->> 'type')
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'activity' then exists (select 1 from "better_supabase"."engagements" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'compliance_policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      else false
    end and "better_supabase"."can_subject"((v_item ->> 'type'), (v_item ->> 'id'), 'read')) then
      raise exception 'a subject is unknown or not readable in this organization' using errcode = '42501', hint = 'ACTIVITY_SUBJECT_FORBIDDEN';
    end if;
  end loop;
  delete from "better_supabase"."engagement_subjects" x where x."engagement_id" = v_id;
  insert into "better_supabase"."engagement_subjects" ("tenant_id", "engagement_id", "subject_type", "subject_id", "position")
  select v_tenant, v_id, s.value ->> 'type', s.value ->> 'id', s.ordinality::integer
  from jsonb_array_elements(coalesce(log_activity.subjects, '[]')) with ordinality s
  on conflict do nothing;
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  perform "better_supabase".emit_event('activity.logged', jsonb_build_object('organizationId', v_tenant, 'engagementId', v_id, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects), 'engagements/' || v_id::text, (v_tenant::text)::text, null, 'better-supabase/activities');
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
    v_hook regprocedure := to_regprocedure('"public"."after_activity_log"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."engagements" x where x."id" = v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.mark_activity_error (
  engagement uuid,
  reason     text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid := mark_activity_error.engagement;
  v_reason text := nullif(trim(mark_activity_error.reason), '');
  v_tenant uuid;
  v_type text;
  v_subjects jsonb := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = mark_activity_error.engagement), '[]'::jsonb);
  v_first jsonb := v_subjects -> 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_reason is null then
    raise exception 'say why the engagement is in error' using errcode = '23502', hint = 'ACTIVITY_REASON_REQUIRED';
  end if;
  if exists (select 1 from "better_supabase"."engagements" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and x."marked_error_at" is not null) then
    raise exception 'the engagement is already marked in error' using errcode = '55000', hint = 'ACTIVITY_ALREADY_MARKED_ERROR';
  end if;
  update "better_supabase"."engagements" x set
    "marked_error_at" = now(),
    "marked_error_by" = auth.uid(),
    "marked_error_reason" = v_reason,
    "locked_at" = least(coalesce(x."locked_at", now()), now())
  where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false))
  returning x."tenant_id", x."type"::text into v_tenant, v_type;
  if v_tenant is null then
    raise exception 'no such engagement you can edit' using errcode = 'P0002', hint = 'ACTIVITY_NOT_FOUND';
  end if;
  perform "better_supabase".emit_event('activity.error_marked', jsonb_build_object('organizationId', v_tenant, 'engagementId', v_id, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects, 'reason', v_reason), 'engagements/' || v_id::text, (v_tenant::text)::text, null, 'better-supabase/activities');
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."engagements" x where x."id" = v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.notify_due_drive_reviews()
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_count integer := 0;
  v_claims text;
begin
  for v_node in
    select * from "better_supabase"."drive_nodes" x
    where x."document_status" = 'effective' and x."next_review_on" <= current_date
      and x."review_notified_for" is distinct from x."next_review_on" and x."deleted_at" is null
    for update skip locked
  loop
    perform "better_supabase".emit_event('drive_node.review_requested', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'documentNumber', v_node."document_number", 'ownerId', v_node."document_owner_id", 'nextReviewOn', v_node."next_review_on"), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive-files');
    if v_node."document_owner_id" is not null then
      v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'drive.document_review_due',
        'tenant', v_node."tenant_id",
        'actor', null,
        'subject_type', 'drive_node',
        'subject_id', v_node."id"::text,
        'summary', v_node."document_number" || ' ' || v_node."name",
        'recipients', to_jsonb(array[v_node."document_owner_id"]),
        'key', 'drive.document_review_due:' || v_node."id"::text || ':' || v_node."next_review_on"::text,
        'data', jsonb_build_object('nodeId', v_node."id", 'documentNumber', v_node."document_number", 'nextReviewOn', v_node."next_review_on")
      ));
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
    update "better_supabase"."drive_nodes" x set "review_notified_for" = v_node."next_review_on" where x."id" = v_node."id";
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.publish_compliance_policy (
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
  select * into v_row from "better_supabase"."policies" x where x."id" = publish_compliance_policy.policy_id for update;
  if not found then
    raise exception 'policy not found' using errcode = 'P0002', hint = 'COMPLIANCE_POLICY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'compliance.manage'), false)) then
    raise exception 'not allowed to manage policies' using errcode = '42501', hint = 'COMPLIANCE_POLICY_FORBIDDEN';
  end if;
  if v_row."archived_at" is not null then
    raise exception 'an archived policy can''t be published' using errcode = '55000', hint = 'COMPLIANCE_POLICY_ARCHIVED';
  end if;
  if publish_compliance_policy.content is null or jsonb_typeof(publish_compliance_policy.content) <> 'object' then
    raise exception 'content must be an object' using errcode = '22023', hint = 'COMPLIANCE_POLICY_INVALID';
  end if;
  v_version := "better_supabase"."version_insert"(
    v_row."tenant_id", 'compliance_policy', v_row."id"::text, publish_compliance_policy.content,
    null, coalesce(publish_compliance_policy.label, v_row."title"), 'manual', true, auth.uid()
  );
  update "better_supabase"."policies" x set "current_version_id" = (v_version ->> 'id')::uuid,
    "version_number" = (v_version ->> 'number')::integer, "published_at" = now(), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  perform "better_supabase".emit_event('compliance_policy.published', jsonb_build_object('organizationId', v_row."tenant_id", 'policyId', v_row."id", 'versionId', v_row."current_version_id", 'number', v_row."version_number"), 'policies/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/compliance');
  perform better_supabase.audit_event(
    event_type => 'compliance_policy.published',
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

CREATE OR REPLACE FUNCTION better_supabase.publish_incident_postmortem (
  incident_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."incidents"%rowtype;
  v_post "better_supabase"."incident_postmortems"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."incidents" x where x."id" = publish_incident_postmortem.incident_id;
  if not found then
    raise exception 'incident not found' using errcode = 'P0002', hint = 'INCIDENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'incidents.manage'), false)) then
    raise exception 'not allowed to publish postmortems' using errcode = '42501', hint = 'INCIDENTS_FORBIDDEN';
  end if;
  if v_row."status" <> 'resolved' then
    raise exception 'only a resolved incident''s postmortem can be published' using errcode = '55000', hint = 'INCIDENT_NOT_RESOLVED';
  end if;
  update "better_supabase"."incident_postmortems" x set "status" = 'published', "published_at" = coalesce(x."published_at", now()), "updated_at" = now()
    where x."incident_id" = v_row."id"
    returning * into v_post;
  if not found then
    raise exception 'the incident has no postmortem' using errcode = 'P0002', hint = 'INCIDENT_POSTMORTEM_NOT_FOUND';
  end if;
  perform "better_supabase".emit_event('incident_postmortem.published', jsonb_build_object('organizationId', v_row."tenant_id", 'postmortemId', v_post."id", 'incidentId', v_row."id"), 'incidents/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/incidents');
  perform better_supabase.audit_event(
    event_type => 'incident_postmortem.published',
    category => 'data',
    target_type => 'incident',
    record_id => v_row."id"::text,
    summary => 'published the postmortem of incident ' || v_row."title",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'postmortemId', v_post."id", 'incidentId', v_row."id")
  );
  return jsonb_build_object('id', v_post."id", 'incidentId', v_post."incident_id", 'summary', v_post."summary", 'impact', v_post."impact", 'rootCause', v_post."root_cause", 'resolution', v_post."resolution", 'actionItems', v_post."action_items", 'status', v_post."status", 'publishedAt', v_post."published_at", 'authorId', v_post."author_id", 'createdAt', v_post."created_at", 'updatedAt', v_post."updated_at");
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
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'workflow_editor.publish'), false))) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
      or not coalesce((select z."restricted" from "better_supabase"."workflow_definitions" z where z."id" = v_row."definition_id"), false)
      or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'workflow_editor.manage'), false))
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
  perform "better_supabase".emit_event('workflow_definition.published', jsonb_build_object('organizationId', v_tenant::text, 'definitionId', v_row."definition_id", 'versionId', v_row."id", 'version', v_row."version"), 'workflows/' || v_row."definition_id"::text, (v_tenant)::text, 'workflow_definition.published:' || v_row."id"::text, 'better-supabase/workflow-editor');
  perform better_supabase.audit_event(
    event_type => 'workflow_definition.published',
    category => 'configuration',
    target_type => 'workflow_version',
    record_id => v_row."id"::text,
    tenant => (v_tenant)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant::text, 'definitionId', v_row."definition_id", 'versionId', v_row."id", 'version', v_row."version"),
    idempotency_key => 'workflow_definition.published:' || v_row."id"::text
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

CREATE OR REPLACE FUNCTION better_supabase.record_enrichment (
  subject_type text,
  subject_id   uuid,
  provider     text,
  result       jsonb,
  fill         boolean DEFAULT true
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_company "better_supabase"."companies";
  v_person "better_supabase"."people";
  v_row "better_supabase"."enrichments";
  v_status text;
  v_data jsonb;
  v_filled text[] := '{}';
  v_domain text;
  v_website text;
  v_phone text;
  v_title text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(result) is distinct from 'object' then
    raise exception 'result must be an object' using errcode = '22023', hint = 'ENRICHMENT_INVALID';
  end if;
  v_status := result ->> 'status';
  if v_status is null or v_status not in ('matched', 'not_found') then
    raise exception 'result.status must be matched or not_found' using errcode = '22023', hint = 'ENRICHMENT_INVALID';
  end if;
  v_data := case when v_status = 'matched' then coalesce(result -> 'data', '{}'::jsonb) else '{}'::jsonb end;
  if jsonb_typeof(v_data) is distinct from 'object' then
    raise exception 'result.data must be an object' using errcode = '22023', hint = 'ENRICHMENT_INVALID';
  end if;
  if record_enrichment.provider is null or record_enrichment.provider !~ '^[a-z][a-z0-9_-]{0,62}$' then
    raise exception 'provider must be a lowercase name' using errcode = '22023', hint = 'ENRICHMENT_INVALID';
  end if;
  if record_enrichment.subject_type = 'company' then
    select * into v_company from "better_supabase"."companies" c
    where c."id" = record_enrichment.subject_id and c."archived_at" is null for update;
    v_tenant := v_company."tenant_id";
  elsif record_enrichment.subject_type = 'person' then
    select * into v_person from "better_supabase"."people" p
    where p."id" = record_enrichment.subject_id and p."archived_at" is null for update;
    v_tenant := v_person."tenant_id";
  else
    raise exception 'subject_type must be the company or the person type' using errcode = '22023', hint = 'ENRICHMENT_SUBJECT_UNKNOWN';
  end if;
  if v_tenant is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'enrichment.run'), false)) then
    raise exception 'No company or person you can enrich has this id' using errcode = 'P0002', hint = 'ENRICHMENT_NOT_FOUND';
  end if;
  if v_status = 'matched' and coalesce(record_enrichment.fill, true) then
    if v_company."id" is not null then
      v_domain := lower(nullif(trim(v_data ->> 'domain'), ''));
      if v_company."domain" is null and v_domain ~ '^[a-z0-9.-]+\.[a-z]{2,}$'
        and not exists (
          select 1 from "better_supabase"."companies" c
          where c."tenant_id" = v_tenant and c."domain" = v_domain and c."archived_at" is null
        ) then
        v_filled := v_filled || 'domain'::text;
      else
        v_domain := null;
      end if;
      v_website := nullif(trim(v_data ->> 'website'), '');
      if v_company."website" is null and length(v_website) <= 2048 then
        v_filled := v_filled || 'website'::text;
      else
        v_website := null;
      end if;
      if cardinality(v_filled) > 0 then
        update "better_supabase"."companies" c set
          "domain" = coalesce(c."domain", v_domain),
          "website" = coalesce(c."website", v_website),
          "updated_at" = now()
        where c."id" = v_company."id";
      end if;
    else
      v_phone := nullif(trim(v_data ->> 'phone'), '');
      if v_person."phone" is null and length(v_phone) <= 50 then
        v_filled := v_filled || 'phone'::text;
      else
        v_phone := null;
      end if;
      v_title := nullif(trim(v_data ->> 'title'), '');
      if v_person."title" is null and length(v_title) <= 300 then
        v_filled := v_filled || 'title'::text;
      else
        v_title := null;
      end if;
      if cardinality(v_filled) > 0 then
        update "better_supabase"."people" p set
          "phone" = coalesce(p."phone", v_phone),
          "title" = coalesce(p."title", v_title),
          "updated_at" = now()
        where p."id" = v_person."id";
      end if;
    end if;
  end if;
  if v_company."id" is not null then
    insert into "better_supabase"."enrichments" ("tenant_id", "company_id", "provider", "status", "data", "filled", "requested_by")
    values (v_tenant, record_enrichment.subject_id, record_enrichment.provider, v_status, v_data, v_filled, auth.uid())
    on conflict on constraint enrichments_company_provider_key do update set
      "status" = excluded."status",
      "data" = excluded."data",
      "filled" = excluded."filled",
      "fetched_at" = now(),
      "requested_by" = excluded."requested_by"
    returning * into v_row;
  else
    insert into "better_supabase"."enrichments" ("tenant_id", "person_id", "provider", "status", "data", "filled", "requested_by")
    values (v_tenant, record_enrichment.subject_id, record_enrichment.provider, v_status, v_data, v_filled, auth.uid())
    on conflict on constraint enrichments_person_provider_key do update set
      "status" = excluded."status",
      "data" = excluded."data",
      "filled" = excluded."filled",
      "fetched_at" = now(),
      "requested_by" = excluded."requested_by"
    returning * into v_row;
  end if;
  if v_company."id" is not null then
    perform "better_supabase".emit_event('company.enriched', jsonb_build_object('organizationId', v_tenant, 'subjectType', record_enrichment.subject_type, 'subjectId', record_enrichment.subject_id, 'provider', record_enrichment.provider, 'status', v_status, 'filled', to_jsonb(v_filled)), 'enrichments/' || v_row."id"::text, (v_tenant::text)::text, null, 'better-supabase/enrichment');
  else
    perform "better_supabase".emit_event('person.enriched', jsonb_build_object('organizationId', v_tenant, 'subjectType', record_enrichment.subject_type, 'subjectId', record_enrichment.subject_id, 'provider', record_enrichment.provider, 'status', v_status, 'filled', to_jsonb(v_filled)), 'enrichments/' || v_row."id"::text, (v_tenant::text)::text, null, 'better-supabase/enrichment');
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', case when v_row."company_id" is not null then 'company' else 'person' end, 'subjectId', coalesce(v_row."company_id", v_row."person_id"), 'provider', v_row."provider", 'status', v_row."status", 'data', v_row."data", 'filled', to_jsonb(v_row."filled"), 'fetchedAt', v_row."fetched_at", 'requestedBy', v_row."requested_by");
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
    raise exception 'No rule has this id' using errcode = 'P0002', hint = 'AUTOMATION_NOT_FOUND';
  end if;
  if coalesce(record_rule_evaluation.mode, 'live') not in ('live', 'test') then
    raise exception 'mode is live or test' using errcode = '22023', hint = 'AUTOMATION_INVALID';
  end if;
  if coalesce(record_rule_evaluation.mode, 'live') = 'live' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role records live evaluations' using errcode = '42501', hint = 'AUTOMATION_FORBIDDEN';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_rule."organization_id", 'automations.write'), false)) then
    raise exception 'Testing rules needs the edit permission' using errcode = '42501', hint = 'AUTOMATION_FORBIDDEN';
  end if;
  insert into "better_supabase"."rule_evaluations" ("organization_id", "rule_id", "version", "subject_type", "subject_id", "trigger", "matched", "results", "mode", "evaluated_by")
  values (v_rule."organization_id", v_rule."id", v_rule."version", v_rule."subject_type", record_rule_evaluation.subject_id, v_rule."trigger",
    coalesce(record_rule_evaluation.matched, false), coalesce(record_rule_evaluation.results, '{}'::jsonb), coalesce(record_rule_evaluation.mode, 'live'), auth.uid())
  returning * into v_row;
  if v_row."mode" = 'live' and v_row."matched" then
    perform "better_supabase".emit_event('automation.matched', jsonb_build_object('organizationId', v_rule."organization_id"::text, 'ruleId', v_rule."id"::text, 'version', v_rule."version", 'subjectType', v_rule."subject_type", 'subjectId', record_rule_evaluation.subject_id, 'trigger', v_rule."trigger"), 'rules/' || v_rule."id"::text, (v_rule."organization_id")::text, null, 'better-supabase/automations');
  end if;
  return jsonb_build_object('id', v_row."id"::text, 'organizationId', v_row."organization_id", 'ruleId', v_row."rule_id", 'version', v_row."version", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'trigger', v_row."trigger", 'matched', v_row."matched", 'results', v_row."results", 'mode', v_row."mode", 'evaluatedBy', v_row."evaluated_by", 'evaluatedAt', v_row."evaluated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.remove_approval_policy (
  policy_id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."approval_policies"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."approval_policies" x where x."id" = remove_approval_policy.policy_id;
  if not found then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'approvals.manage'), false)) then
    raise exception 'managing approval policies needs approvals.manage' using errcode = '42501', hint = 'APPROVAL_FORBIDDEN';
  end if;
  delete from "better_supabase"."approval_policies" x where x."id" = v_row."id";
  perform "better_supabase".emit_event('approval_policy.deleted', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'subjectType', v_row."subject_type", 'action', v_row."action"), 'approval-policies/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/approvals');
  perform better_supabase.audit_event(
    event_type => 'approval_policy.deleted',
    category => 'configuration',
    target_type => 'approval_policy',
    record_id => v_row."id"::text,
    summary => 'removed approval policy ' || v_row."name",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'subjectType', v_row."subject_type", 'action', v_row."action")
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.remove_organization_domain (
  id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."organization_domains";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."organization_domains" x where x."id" = remove_organization_domain.id;
  if v_row."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'sso.manage'), false)) then
    return false;
  end if;
  if exists (select 1 from "better_supabase"."organization_sso_providers" sp where sp."organization_id" = v_row."organization_id" and v_row."domain" = any (sp."domains")) then
    raise exception 'An SSO provider uses this domain; remove it first' using errcode = '23503', hint = 'SSO_DOMAIN_IN_USE';
  end if;
  delete from "better_supabase"."organization_domains" x where x."id" = v_row."id";
  perform "better_supabase".emit_event('sso_domain.deleted', jsonb_build_object('organizationId', v_row."organization_id"::text, 'domainId', v_row."id", 'domain', v_row."domain", 'userId', auth.uid()), 'organizations/' || v_row."organization_id"::text, (v_row."organization_id")::text, null, 'better-supabase/sso');
  perform better_supabase.audit_event(
    event_type => 'sso_domain.deleted',
    category => 'security',
    target_type => 'domain',
    record_id => v_row."id"::text,
    target_label => v_row."domain",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'domainId', v_row."id", 'domain', v_row."domain", 'userId', auth.uid()),
    actor_id => auth.uid()
  );
  return true;
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
  if v_row."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'automations.manage'), false)) then
    return false;
  end if;
  if v_row."default_key" is not null then
    raise exception 'A block ships this automation; turn it off instead of removing it' using errcode = '22023', hint = 'AUTOMATION_DEFAULT';
  end if;
  delete from "better_supabase"."rules" x where x."id" = v_row."id";
  perform "better_supabase".emit_event('automation.deleted', jsonb_build_object('organizationId', v_row."organization_id"::text, 'ruleId', v_row."id"::text, 'name', v_row."name", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'version', v_row."version"), 'rules/' || v_row."id"::text, (v_row."organization_id")::text, null, 'better-supabase/automations');
  perform better_supabase.audit_event(
    event_type => 'automation.deleted',
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

CREATE OR REPLACE FUNCTION better_supabase.remove_segment (
  segment uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."segments";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."segments" x where x."id" = remove_segment.segment;
  if v_row."id" is null then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'segments.write'), false)) then
    raise exception 'You need segments.edit to remove a segment' using errcode = '42501', hint = 'SEGMENT_FORBIDDEN';
  end if;
  delete from "better_supabase"."segments" x where x."id" = v_row."id";
  perform "better_supabase".emit_event('segment.deleted', jsonb_build_object('organizationId', v_row."tenant_id", 'segmentId', v_row."id", 'subjectType', v_row."subject_type", 'name', v_row."name"), 'segments/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/segments');
  perform better_supabase.audit_event(
    event_type => 'segment.deleted',
    category => 'data',
    target_type => 'segment',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."tenant_id"::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'segmentId', v_row."id", 'subjectType', v_row."subject_type", 'name', v_row."name")
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.request_access (
  tenant   uuid,
  role     text,
  reason   text     DEFAULT NULL::text,
  duration interval DEFAULT NULL::interval
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  SET "IntervalStyle" TO 'iso_8601'
  AS $function$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_current text;
  v_duration interval;
  v_row "better_supabase"."access_requests"%rowtype;
  v_approval jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null then
    raise exception 'sign in to request access' using errcode = '42501', hint = 'ACCESS_SIGN_IN';
  end if;
  select (select r."key" from "better_supabase"."roles" r where r."id" = m."role") into v_current from "public"."memberships" m
  where m."organization_id" = request_access.tenant and m."user_id" = v_me;
  if not found then
    raise exception 'only members can request a role' using errcode = '42501', hint = 'ACCESS_REQUEST_FORBIDDEN';
  elsif not coalesce(better_supabase.can('tenant', request_access.tenant, 'access_requests.create'), false) then
    raise exception 'not allowed to request a role here' using errcode = '42501', hint = 'ACCESS_REQUEST_FORBIDDEN';
  end if;
  if not (request_access.role = any (array['admin', 'member', 'viewer']::text[])) then
    raise exception 'this role can''t be requested' using errcode = '22023', hint = 'ACCESS_ROLE_INVALID';
  end if;
  if v_current = request_access.role then
    raise exception 'you already hold this role' using errcode = '22023', hint = 'ACCESS_ROLE_HELD';
  end if;
  if v_current = 'owner' then
    raise exception 'an owner can''t request another role' using errcode = '22023', hint = 'ACCESS_ROLE_INVALID';
  end if;
  v_duration := request_access.duration;
  if v_duration is not null and v_duration <= interval '0' then
    raise exception 'duration must be positive' using errcode = '22023', hint = 'ACCESS_DURATION_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('access_request:' || request_access.tenant::text || ':' || v_me::text, 0));
  if exists (
    select 1 from "better_supabase"."access_requests" r join "better_supabase"."approval_requests" x on x."id" = r."approval_id"
    where r."tenant_id" = request_access.tenant and r."user_id" = v_me and x."status" = 'pending' and r."target" = 'role'
  ) then
    raise exception 'you already have a pending access request here' using errcode = '23505', hint = 'ACCESS_REQUEST_PENDING';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_access_request"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using request_access.tenant, request_access.role;
    end if;
  end;
  insert into "better_supabase"."access_requests" ("tenant_id", "user_id", "role", "reason", "duration")
  values (request_access.tenant, v_me, request_access.role, request_access.reason, v_duration)
  returning * into v_row;
  v_approval := "better_supabase"."open_approval"(
    request_access.tenant, 'access_request', v_row."id"::text, 'grant',
    '{"steps":[{"approvers":{"permission":"members.update_role"},"required":1}],"selfApproval":false,"expiresIn":null,"run":null}'::jsonb, request_access.reason,
    jsonb_build_object('role', request_access.role, 'userId', v_me, 'duration', v_duration::text)
  );
  update "better_supabase"."access_requests" r set "approval_id" = (v_approval ->> 'id')::uuid
  where r."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('access_request.requested', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'userId', v_row."user_id", 'role', v_row."role", 'id', v_row."id", 'approvalId', v_row."approval_id", 'expiresAt', v_row."expires_at", 'target', v_row."target", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'action', v_row."action"), 'access-requests/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/access-requests');
  perform better_supabase.audit_event(
    event_type => 'access_request.requested',
    category => 'membership',
    target_type => 'user',
    record_id => v_row."user_id"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'userId', v_row."user_id", 'role', v_row."role", 'id', v_row."id", 'approvalId', v_row."approval_id", 'expiresAt', v_row."expires_at", 'target', v_row."target", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'action', v_row."action")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_access_request"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'role', v_row."role", 'target', v_row."target", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'action', v_row."action", 'emergency', v_row."emergency", 'review', case when v_row."reviewed_at" is null then null else jsonb_build_object('verdict', v_row."review_verdict", 'note', v_row."review_note", 'reviewedBy', v_row."reviewed_by", 'reviewedAt', v_row."reviewed_at") end, 'previousRole', v_row."previous_role", 'reason', v_row."reason", 'duration', v_row."duration"::text, 'status', 'pending', 'approvalId', v_row."approval_id", 'grantedAt', v_row."granted_at", 'expiresAt', v_row."expires_at", 'endedAt', v_row."ended_at", 'createdAt', v_row."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.request_record_access (
  subject_type text,
  subject_id   text,
  action       text     DEFAULT 'read'::text,
  reason       text     DEFAULT NULL::text,
  duration     interval DEFAULT '7 days'::interval
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  SET "IntervalStyle" TO 'iso_8601'
  AS $function$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_tenant uuid;
  v_duration interval := coalesce(request_record_access.duration, interval '7 days');
  v_leads uuid[];
  v_row "better_supabase"."access_requests"%rowtype;
  v_approval jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null then
    raise exception 'sign in to request access' using errcode = '42501', hint = 'ACCESS_SIGN_IN';
  end if;
  if not (request_record_access.subject_type = any (array['customer', 'drive_node']::text[])) or (case request_record_access.subject_type
      when 'customer' then not (request_record_access.action = any (array['read', 'write']::text[]))
      when 'drive_node' then not (request_record_access.action = any (array['read']::text[]))
      else true end) then
    raise exception 'this record or action can''t be requested' using errcode = '22023', hint = 'ACCESS_REQUEST_RECORD_INVALID';
  end if;
  v_tenant := "better_supabase"."record_team_tenant"(request_record_access.subject_type, request_record_access.subject_id);
  if v_tenant is null then
    raise exception 'record not found' using errcode = 'P0002', hint = 'ACCESS_REQUEST_RECORD_INVALID';
  end if;
  if not exists (select 1 from "public"."memberships" m where m."organization_id" = v_tenant and m."user_id" = auth.uid()) or not coalesce(better_supabase.can('tenant', v_tenant, 'access_requests.create'), false) then
    raise exception 'not allowed to request access here' using errcode = '42501', hint = 'ACCESS_REQUEST_FORBIDDEN';
  end if;
  if "better_supabase"."can_subject"(request_record_access.subject_type, request_record_access.subject_id, request_record_access.action) then
    raise exception 'you already have this access' using errcode = '22023', hint = 'ACCESS_REQUEST_RECORD_INVALID';
  end if;
  if v_duration <= interval '0' then
    raise exception 'duration must be positive' using errcode = '22023', hint = 'ACCESS_DURATION_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('access_request:' || request_record_access.subject_type || ':' || request_record_access.subject_id || ':' || v_me::text, 0));
  if exists (
    select 1 from "better_supabase"."access_requests" r join "better_supabase"."approval_requests" x on x."id" = r."approval_id"
    where r."subject_type" = request_record_access.subject_type and r."subject_id" = request_record_access.subject_id
      and r."user_id" = v_me and x."status" = 'pending'
  ) then
    raise exception 'you already have a pending access request for this record' using errcode = '23505', hint = 'ACCESS_REQUEST_PENDING';
  end if;
  insert into "better_supabase"."access_requests" ("tenant_id", "user_id", "target", "subject_type", "subject_id", "action", "reason", "duration")
  values (v_tenant, v_me, 'record', request_record_access.subject_type, request_record_access.subject_id, request_record_access.action, request_record_access.reason, v_duration)
  returning * into v_row;
  v_leads := "better_supabase"."record_team_leads"(request_record_access.subject_type, request_record_access.subject_id);
  if coalesce(cardinality(v_leads), 0) = 0 then
    v_leads := case request_record_access.subject_type
      when 'drive_node' then array_remove("better_supabase"."drive_access_approvers"(request_record_access.subject_id), v_me)
      else v_leads end;
  end if;
  v_approval := "better_supabase"."open_approval"(
    v_tenant, 'access_request', v_row."id"::text, 'grant',
    '{"steps":[{"approvers":{"permission":"members.update_role"},"required":1}],"selfApproval":false,"expiresIn":null,"run":null}'::jsonb || jsonb_build_object('steps', jsonb_build_array(jsonb_build_object(
      'approvers', case when cardinality(v_leads) > 0 then jsonb_build_object('users', to_jsonb(v_leads)) else jsonb_build_object('permission', 'subjects.manage') end,
      'required', 1))),
    request_record_access.reason,
    jsonb_build_object('subjectType', request_record_access.subject_type, 'subjectId', request_record_access.subject_id, 'action', request_record_access.action, 'userId', v_me, 'duration', v_duration::text)
  );
  update "better_supabase"."access_requests" r set "approval_id" = (v_approval ->> 'id')::uuid
  where r."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('access_request.requested', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'userId', v_row."user_id", 'role', v_row."role", 'id', v_row."id", 'approvalId', v_row."approval_id", 'expiresAt', v_row."expires_at", 'target', v_row."target", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'action', v_row."action"), 'access-requests/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/access-requests');
  perform better_supabase.audit_event(
    event_type => 'access_request.requested',
    category => 'membership',
    target_type => 'user',
    record_id => v_row."user_id"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'userId', v_row."user_id", 'role', v_row."role", 'id', v_row."id", 'approvalId', v_row."approval_id", 'expiresAt', v_row."expires_at", 'target', v_row."target", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'action', v_row."action")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'role', v_row."role", 'target', v_row."target", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'action', v_row."action", 'emergency', v_row."emergency", 'review', case when v_row."reviewed_at" is null then null else jsonb_build_object('verdict', v_row."review_verdict", 'note', v_row."review_note", 'reviewedBy', v_row."reviewed_by", 'reviewedAt', v_row."reviewed_at") end, 'previousRole', v_row."previous_role", 'reason', v_row."reason", 'duration', v_row."duration"::text, 'status', 'pending', 'approvalId', v_row."approval_id", 'grantedAt', v_row."granted_at", 'expiresAt', v_row."expires_at", 'endedAt', v_row."ended_at", 'createdAt', v_row."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.reset_default_rule (
  id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."rules";
  v_default "better_supabase"."rule_defaults";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."rules" x where x."id" = reset_default_rule.id for update;
  if v_row."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'automations.read'), false)) then
    raise exception 'No rule you can read has this id' using errcode = 'P0002', hint = 'AUTOMATION_NOT_FOUND';
  end if;
  select * into v_default from "better_supabase"."rule_defaults" x where x."key" = v_row."default_key";
  if v_default."key" is null then
    raise exception 'No block ships this rule' using errcode = '22023', hint = 'AUTOMATION_NOT_DEFAULT';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (case when (v_row."enabled" or v_default."enabled") then coalesce(better_supabase.can('tenant', v_row."organization_id", 'automations.publish'), false) else coalesce(better_supabase.can('tenant', v_row."organization_id", 'automations.write'), false) end)) then
    raise exception 'You need % to reset this rule', case when (v_row."enabled" or v_default."enabled") then '''automations.publish''' else '''automations.write''' end using errcode = '42501', hint = 'AUTOMATION_FORBIDDEN';
  end if;
  update "better_supabase"."rules" x set
    "trigger" = v_default."trigger",
    "name" = v_default."name",
    "description" = v_default."description",
    "conditions" = v_default."conditions",
    "actions" = v_default."actions",
    "enabled" = v_default."enabled",
    "stop_processing" = false,
    "version" = x."version" + 1,
    "updated_by" = auth.uid(),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  insert into "better_supabase"."rule_versions" ("rule_id", "version", "organization_id", "name", "conditions", "actions", "saved_by")
  values (v_row."id", v_row."version", v_row."organization_id", v_row."name", v_row."conditions", v_row."actions", auth.uid())
  on conflict do nothing;
  perform "better_supabase".emit_event('automation.updated', jsonb_build_object('organizationId', v_row."organization_id"::text, 'ruleId', v_row."id"::text, 'name', v_row."name", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'version', v_row."version"), 'rules/' || v_row."id"::text, (v_row."organization_id")::text, null, 'better-supabase/automations');
  perform better_supabase.audit_event(
    event_type => 'automation.updated',
    category => 'configuration',
    target_type => 'rule',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'ruleId', v_row."id"::text, 'name', v_row."name", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'version', v_row."version"),
    actor_id => auth.uid()
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."organization_id", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'name', v_row."name", 'description', v_row."description", 'conditions', v_row."conditions", 'actions', v_row."actions", 'enabled', v_row."enabled", 'stopProcessing', v_row."stop_processing", 'rank', v_row."rank", 'version', v_row."version", 'createdBy', v_row."created_by", 'updatedBy', v_row."updated_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'defaultKey', v_row."default_key");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.rotate_webhook_secret (
  endpoint uuid,
  overlap  interval DEFAULT '24:00:00'::interval,
  secret   text     DEFAULT NULL::text
)
  RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_enabled boolean;
  v_secret text := coalesce(
    rotate_webhook_secret.secret,
    'whsec_' || encode(extensions.gen_random_bytes(32), 'base64')
  );
  v_vault uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select d."organization_id", d."enabled" into v_tenant, v_enabled
  from "better_supabase"."webhook_endpoints" d where d."id" = rotate_webhook_secret.endpoint;
  if not found then
    raise exception 'Webhook endpoint not found' using errcode = 'P0002', hint = 'WEBHOOK_ENDPOINT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not coalesce(better_supabase.can('tenant', v_tenant, 'webhooks.manage'), false) then
    raise exception 'Not allowed to manage this webhook endpoint' using errcode = '42501', hint = 'WEBHOOK_FORBIDDEN';
  end if;
  if length(v_secret) < 16 then
    raise exception 'A webhook secret needs at least 16 characters' using errcode = '22023', hint = 'WEBHOOK_SECRET_TOO_SHORT';
  end if;
  delete from vault.secrets vs using "better_supabase"."webhook_endpoint_secrets" s where vs.id = s."vault_secret_id" and s."endpoint_id" = rotate_webhook_secret.endpoint and s."expires_at" <= now();
  delete from "better_supabase"."webhook_endpoint_secrets" s where s."endpoint_id" = rotate_webhook_secret.endpoint and s."expires_at" <= now();
  update "better_supabase"."webhook_endpoint_secrets" s set "expires_at" = now() + coalesce(rotate_webhook_secret.overlap, '24 hours')
  where s."endpoint_id" = rotate_webhook_secret.endpoint and s."expires_at" is null;
  v_vault := vault.create_secret(
    v_secret,
    'webhook:' || rotate_webhook_secret.endpoint::text || ':' || gen_random_uuid()::text,
    'better-supabase outgoing webhook signing secret'
  );
  insert into "better_supabase"."webhook_endpoint_secrets" ("endpoint_id", "vault_secret_id", "organization_id")
  values (rotate_webhook_secret.endpoint, v_vault, v_tenant);
  perform "better_supabase".emit_event('webhook_endpoint.secret_rotated', jsonb_build_object('endpointId', rotate_webhook_secret.endpoint, 'organizationId', v_tenant::text), 'webhooks/' || rotate_webhook_secret.endpoint::text, (v_tenant)::text, null, 'better-supabase/webhooks-out');
  perform better_supabase.audit_event(
    event_type => 'webhook_endpoint.secret_rotated',
    category => 'security',
    target_type => 'webhook_endpoint',
    record_id => rotate_webhook_secret.endpoint::text,
    tenant => (v_tenant)::uuid,
    metadata => jsonb_build_object('endpointId', rotate_webhook_secret.endpoint, 'organizationId', v_tenant::text)
  );
  return v_secret;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_activity_notes (
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
  v_summary text := nullif(trim(save_activity_notes.notes ->> 'summary'), '');
  v_items jsonb := coalesce(save_activity_notes.notes -> 'actionItems', '[]'::jsonb);
  v_subjects jsonb;
  v_first jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."type" into v_tenant, v_type
  from "better_supabase"."engagements" x where x."id" = save_activity_notes.engagement and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false));
  if v_tenant is null then
    raise exception 'no such engagement you can edit' using errcode = 'P0002', hint = 'ACTIVITY_NOT_FOUND';
  end if;
  if v_summary is null or length(v_summary) > 20000 then
    raise exception 'notes need a summary of at most 20000 characters' using errcode = '22023', hint = 'ACTIVITY_NOTES_INVALID';
  end if;
  if jsonb_typeof(v_items) <> 'array' or exists (
    select 1 from jsonb_array_elements(v_items) i
    where jsonb_typeof(i.value) <> 'object' or jsonb_typeof(i.value -> 'text') is distinct from 'string'
  ) then
    raise exception 'actionItems must be a list of { text }' using errcode = '22023', hint = 'ACTIVITY_NOTES_INVALID';
  end if;
  insert into "better_supabase"."engagement_notes" ("engagement_id", "tenant_id", "summary", "action_items", "model", "source", "created_by")
  values (save_activity_notes.engagement, v_tenant, v_summary, v_items, nullif(save_activity_notes.notes ->> 'model', ''), case when save_activity_notes.notes ->> 'source' = 'member' then 'member' else 'ai' end, auth.uid())
  on conflict ("engagement_id") do update set
    "summary" = excluded."summary", "action_items" = excluded."action_items",
    "model" = excluded."model", "source" = excluded."source", "updated_at" = now();
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = save_activity_notes.engagement), '[]'::jsonb);
  v_first := v_subjects -> 0;
  perform "better_supabase".emit_event('activity.summarized', jsonb_build_object('organizationId', v_tenant, 'engagementId', save_activity_notes.engagement, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects), 'engagements/' || save_activity_notes.engagement::text, (v_tenant::text)::text, 'activity.summarized:' || save_activity_notes.engagement::text || ':' || md5(save_activity_notes.notes::text), 'better-supabase/activities');
  return (select jsonb_build_object('engagementId', nx."engagement_id", 'organizationId', nx."tenant_id", 'summary', nx."summary", 'actionItems', nx."action_items", 'model', nx."model", 'source', nx."source", 'createdBy', nx."created_by", 'createdAt', nx."created_at", 'updatedAt', nx."updated_at") from "better_supabase"."engagement_notes" nx where nx."engagement_id" = save_activity_notes.engagement);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_activity_transcript (
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
  v_recording uuid := save_activity_transcript.recording;
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
  where rx."id" = v_recording and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false))
  for update of rx;
  if v_engagement is null then
    raise exception 'no such recording you can edit' using errcode = 'P0002', hint = 'ACTIVITY_RECORDING_NOT_FOUND';
  end if;
  if jsonb_typeof(save_activity_transcript.segments) is distinct from 'array'
    or jsonb_array_length(save_activity_transcript.segments) > 20000 then
    raise exception 'segments must be a list of at most 20000 { startMs, endMs, text }' using errcode = '22023', hint = 'ACTIVITY_TRANSCRIPT_INVALID';
  end if;
  for v_item, v_position in select value, ordinality from jsonb_array_elements(save_activity_transcript.segments) with ordinality loop
    if jsonb_typeof(v_item) is distinct from 'object'
      or jsonb_typeof(v_item -> 'text') is distinct from 'string'
      or jsonb_typeof(v_item -> 'startMs') is distinct from 'number'
      or jsonb_typeof(v_item -> 'endMs') is distinct from 'number'
      or (v_item ->> 'startMs')::numeric < 0
      or (v_item ->> 'endMs')::numeric < (v_item ->> 'startMs')::numeric
      or jsonb_typeof(coalesce(v_item -> 'confidence', 'null')) not in ('number', 'null') then
      raise exception 'segment % needs startMs <= endMs and a text', v_position using errcode = '22023', hint = 'ACTIVITY_TRANSCRIPT_INVALID';
    end if;
  end loop;
  delete from "better_supabase"."engagement_transcript_segments" sx where sx."recording_id" = v_recording;
  insert into "better_supabase"."engagement_transcript_segments" ("recording_id", "tenant_id", "position", "speaker", "speaker_user_id", "starts_ms", "ends_ms", "text", "confidence")
  select v_recording, v_tenant, i.ordinality::integer, nullif(i.value ->> 'speaker', ''), nullif(i.value ->> 'speakerUserId', '')::uuid, round((i.value ->> 'startMs')::numeric)::integer, round((i.value ->> 'endMs')::numeric)::integer, i.value ->> 'text', (i.value ->> 'confidence')::real
  from jsonb_array_elements(save_activity_transcript.segments) with ordinality i;
  update "better_supabase"."engagement_recordings" rx set
    "status" = 'transcribed',
    "error" = null,
    "language" = coalesce(nullif(save_activity_transcript.attrs ->> 'language', ''), rx."language"),
    "duration_seconds" = coalesce((save_activity_transcript.attrs ->> 'durationSeconds')::integer, rx."duration_seconds"),
    "model" = coalesce(nullif(save_activity_transcript.attrs ->> 'model', ''), rx."model"),
    "transcribed_at" = now()
  where rx."id" = v_recording;
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = v_engagement), '[]'::jsonb);
  v_first := v_subjects -> 0;
  perform "better_supabase".emit_event('activity.transcribed', jsonb_build_object('organizationId', v_tenant, 'engagementId', v_engagement, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects, 'recordingId', v_recording), 'engagements/' || v_engagement::text, (v_tenant::text)::text, 'activity.transcribed:' || v_recording::text || ':' || md5(save_activity_transcript.segments::text), 'better-supabase/activities');
  return (select jsonb_build_object('id', rx."id", 'organizationId', rx."tenant_id", 'engagementId', rx."engagement_id", 'fileId', rx."file_id", 'filename', rx."filename", 'mediaType', rx."media_type", 'status', rx."status", 'language', rx."language", 'durationSeconds', rx."duration_seconds", 'error', rx."error", 'model', rx."model", 'segmentCount', (select count(*)::integer from "better_supabase"."engagement_transcript_segments" sc where sc."recording_id" = rx."id"), 'createdBy', rx."created_by", 'createdAt', rx."created_at", 'transcribedAt', rx."transcribed_at") from "better_supabase"."engagement_recordings" rx where rx."id" = v_recording);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_agent (
  tenant uuid,
  id     uuid  DEFAULT NULL::uuid,
  fields jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."agents"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(save_agent.fields) is distinct from 'object' then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  if save_agent.id is null then
    if auth.uid() is null or not coalesce(better_supabase.can('tenant', save_agent.tenant, 'agents.write'), false) then
      raise exception 'you may not create agents here' using errcode = '42501', hint = 'AGENT_FORBIDDEN';
    end if;
    if save_agent.fields ->> 'slug' is null or save_agent.fields ->> 'name' is null then
      raise exception 'a new agent needs a slug and a name' using errcode = '22023', hint = 'AGENT_INVALID';
    end if;
    insert into "better_supabase"."agents" ("organization_id", "owner_id", "slug", "name")
    values (save_agent.tenant, auth.uid(), save_agent.fields ->> 'slug', save_agent.fields ->> 'name')
    returning * into v_row;
  else
    select * into v_row from "better_supabase"."agents" x where x."id" = save_agent.id and x."organization_id" = save_agent.tenant for update;
    if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."owner_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."organization_id", 'agents.moderate'), false)) then
      raise exception 'agent % not found', save_agent.id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
    end if;
  end if;
  update "better_supabase"."agents" x set
    "slug" = coalesce(save_agent.fields ->> 'slug', x."slug"),
    "name" = coalesce(save_agent.fields ->> 'name', x."name"),
    "description" = coalesce(save_agent.fields ->> 'description', x."description"),
    "instructions" = coalesce(save_agent.fields ->> 'instructions', x."instructions"),
    "model" = case when save_agent.fields ? 'model' then save_agent.fields ->> 'model' else x."model" end,
    "tools" = coalesce(save_agent.fields -> 'tools', x."tools"),
    "connector_ids" = case when save_agent.fields ? 'connector_ids'
      then array(select jsonb_array_elements_text(save_agent.fields -> 'connector_ids')::uuid)
      else x."connector_ids" end,
    "knowledge_scope" = coalesce(save_agent.fields -> 'knowledge_scope', x."knowledge_scope"),
    "starters" = coalesce(save_agent.fields -> 'starters', x."starters"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  if save_agent.id is null then
    perform "better_supabase".emit_event('agent.created', jsonb_build_object('organizationId', v_row."organization_id"::text, 'agentId', v_row."id", 'slug', v_row."slug"), 'organizations/' || v_row."organization_id"::text || '/agents/' || v_row."id"::text, (v_row."organization_id")::text, null, 'better-supabase/agents');
  perform better_supabase.audit_event(
    event_type => 'agent.created',
    category => 'ai',
    target_type => 'agent',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'agentId', v_row."id", 'slug', v_row."slug")
  );
  else
    perform "better_supabase".emit_event('agent.updated', jsonb_build_object('organizationId', v_row."organization_id"::text, 'agentId', v_row."id", 'slug', v_row."slug"), 'organizations/' || v_row."organization_id"::text || '/agents/' || v_row."id"::text, (v_row."organization_id")::text, null, 'better-supabase/agents');
  perform better_supabase.audit_event(
    event_type => 'agent.updated',
    category => 'ai',
    target_type => 'agent',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'agentId', v_row."id", 'slug', v_row."slug")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
exception
  when unique_violation then
    raise exception 'an agent with slug % exists', save_agent.fields ->> 'slug' using errcode = '23505', hint = 'AGENT_SLUG_TAKEN';
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
  v_inserted boolean;
  v_row "better_supabase"."ai_provider_keys"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_ai_provider_key.tenant, 'ai_keys.manage'), false)) then
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
  v_inserted := not found;
  insert into "better_supabase"."ai_provider_keys" ("organization_id", "provider", "name", "credential_ref", "settings", "enabled", "created_by")
  values (save_ai_provider_key.tenant, save_ai_provider_key.provider, coalesce(save_ai_provider_key.name, 'default'), save_ai_provider_key.credential_ref, coalesce(save_ai_provider_key.settings, '{}'), coalesce(save_ai_provider_key.enabled, true), auth.uid())
  on conflict ("organization_id", "provider", "name") do update set
    "credential_ref" = excluded."credential_ref",
    "settings" = excluded."settings",
    "enabled" = excluded."enabled",
    "updated_at" = now()
  returning * into v_row;
  if v_inserted then
    perform "better_supabase".emit_event('ai_provider_key.created', jsonb_build_object('organizationId', v_row."organization_id"::text, 'keyId', v_row."id", 'provider', v_row."provider", 'name', v_row."name"), 'organizations/' || v_row."organization_id"::text || '/ai-provider-keys/' || v_row."id"::text, (v_row."organization_id")::text, null, 'better-supabase/ai-keys');
  perform better_supabase.audit_event(
    event_type => 'ai_provider_key.created',
    category => 'security',
    target_type => 'ai_provider_key',
    record_id => v_row."id"::text,
    target_label => v_row."provider" || '/' || v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'keyId', v_row."id", 'provider', v_row."provider", 'name', v_row."name")
  );
  else
    perform "better_supabase".emit_event('ai_provider_key.updated', jsonb_build_object('organizationId', v_row."organization_id"::text, 'keyId', v_row."id", 'provider', v_row."provider", 'name', v_row."name"), 'organizations/' || v_row."organization_id"::text || '/ai-provider-keys/' || v_row."id"::text, (v_row."organization_id")::text, null, 'better-supabase/ai-keys');
  perform better_supabase.audit_event(
    event_type => 'ai_provider_key.updated',
    category => 'security',
    target_type => 'ai_provider_key',
    record_id => v_row."id"::text,
    target_label => v_row."provider" || '/' || v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'keyId', v_row."id", 'provider', v_row."provider", 'name', v_row."name")
  );
  end if;
  return jsonb_build_object('key', jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'provider', v_row."provider", 'name', v_row."name", 'credential_ref', v_row."credential_ref", 'settings', v_row."settings", 'enabled', v_row."enabled", 'created_by', v_row."created_by", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at"), 'replaced', v_old);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_announcement (
  id     uuid,
  fields jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."announcements";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('announcements.manage'), false))) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  if save_announcement.id is null then
    v_row := jsonb_populate_record(null::"better_supabase"."announcements", jsonb_build_object(
      'id', gen_random_uuid(),
      'body', '',
      'severity', 'info',
      'audience', 'all',
      'targets', '{}'::text[],
      'starts_at', now(),
      'dismissible', true,
      'created_by', auth.uid(),
      'created_at', now()
    ) || save_announcement.fields);
    v_row."updated_at" := now();
    insert into "better_supabase"."announcements" select v_row.* returning * into v_row;
  else
    select * into v_row from "better_supabase"."announcements" x where x."id" = save_announcement.id for update;
    if v_row."id" is null then
      raise exception 'No announcement %', save_announcement.id using errcode = 'P0002', hint = 'ANNOUNCEMENT_NOT_FOUND';
    end if;
    v_row := jsonb_populate_record(v_row, save_announcement.fields - 'id' - 'created_by' - 'created_at');
    v_row."updated_at" := now();
    update "better_supabase"."announcements" x set ("title", "body", "severity", "href", "audience", "targets", "starts_at", "ends_at", "dismissible", "updated_at") = (v_row."title", v_row."body", v_row."severity", v_row."href", v_row."audience", v_row."targets", v_row."starts_at", v_row."ends_at", v_row."dismissible", v_row."updated_at")
    where x."id" = v_row."id"
    returning * into v_row;
  end if;
  if save_announcement.id is null then
    perform "better_supabase".emit_event('announcement.created', jsonb_build_object('announcementId', v_row."id"), 'announcements/' || v_row."id"::text, null, null, 'better-supabase/announcements');
  perform better_supabase.audit_event(
    event_type => 'announcement.created',
    category => 'configuration',
    target_type => 'announcement',
    record_id => v_row."id"::text,
    metadata => jsonb_build_object('announcementId', v_row."id")
  );
  else
    perform "better_supabase".emit_event('announcement.updated', jsonb_build_object('announcementId', v_row."id"), 'announcements/' || v_row."id"::text, null, null, 'better-supabase/announcements');
  perform better_supabase.audit_event(
    event_type => 'announcement.updated',
    category => 'configuration',
    target_type => 'announcement',
    record_id => v_row."id"::text,
    metadata => jsonb_build_object('announcementId', v_row."id")
  );
  end if;
  return to_jsonb(v_row);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_approval_policy (
  tenant uuid,
  policy jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_old "better_supabase"."approval_policies"%rowtype;
  v_row "better_supabase"."approval_policies"%rowtype;
  v_type text;
  v_action text;
  v_conditions jsonb;
  v_steps jsonb;
  v_step jsonb;
  v_fields jsonb;
  v_effect text;
  v_who jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_approval_policy.tenant, 'approvals.manage'), false)) then
    raise exception 'managing approval policies needs approvals.manage' using errcode = '42501', hint = 'APPROVAL_FORBIDDEN';
  end if;
  if jsonb_typeof(save_approval_policy.policy) is distinct from 'object' then
    raise exception 'policy must be an object' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
  end if;
  if save_approval_policy.policy ? 'id' then
    select * into v_old from "better_supabase"."approval_policies" x
    where x."id" = (save_approval_policy.policy ->> 'id')::uuid and x."tenant_id" is not distinct from save_approval_policy.tenant
    for update;
    if not found then
      raise exception 'approval policy not found' using errcode = 'P0002', hint = 'APPROVAL_POLICY_NOT_FOUND';
    end if;
  end if;
  v_type := coalesce(save_approval_policy.policy ->> 'subjectType', v_old."subject_type");
  v_action := coalesce(save_approval_policy.policy ->> 'action', v_old."action");
  v_effect := case when save_approval_policy.policy ? 'effect' then nullif(save_approval_policy.policy ->> 'effect', '') else v_old."effect" end;
  if v_type is null or v_action is null or not (exists (
      select 1 from jsonb_array_elements('[{"subjectType":"*","action":"quote.send","effects":["money-movement"]},{"subjectType":"customer","action":"discount","effects":[]},{"subjectType":"customer","action":"refund","effects":[]},{"subjectType":"customer","action":"export","effects":[]},{"subjectType":"drive_node","action":"approve","effects":[]},{"subjectType":"drive_node","action":"release","effects":[]},{"subjectType":"eve_tool_call","action":"add_note","effects":[]},{"subjectType":"workflow_run","action":"approve","effects":[]}]'::jsonb) f
      where (v_type = '*' or f.value ->> 'subjectType' in (v_type, '*'))
        and (v_action = '*' or f.value ->> 'action' in (v_action, '*'))
        and (v_effect is null or f.value -> 'effects' ? v_effect)
    )) then
    raise exception 'a tenant policy tightens an options.policies entry, and there is none for this subject type, action and effect' using errcode = '22023', hint = 'APPROVAL_POLICY_UNKNOWN';
  end if;
  v_conditions := case when save_approval_policy.policy ? 'conditions' then nullif(save_approval_policy.policy -> 'conditions', 'null'::jsonb) else v_old."conditions" end;
  if v_conditions is not null then
    v_fields := "better_supabase"."rule_field_map"(v_type);
    if v_fields = '{}'::jsonb then
      raise exception 'no rule fields for this subject type; sync them first' using errcode = '22023', hint = 'APPROVAL_FIELDS_MISSING';
    end if;
    perform "better_supabase"."rule_check"(v_conditions, v_fields, 1);
  end if;
  v_steps := coalesce(save_approval_policy.policy -> 'steps', v_old."steps", '[]'::jsonb);
  if jsonb_typeof(v_steps) <> 'array' or jsonb_array_length(v_steps) > 20 then
    raise exception 'steps must be a list of { approvers: { permission, role, team, users, manager }, required, escalateAfter, escalateTo } objects' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
  end if;
  for v_step in select * from jsonb_array_elements(v_steps) loop
    if jsonb_typeof(v_step) <> 'object' then
      raise exception 'steps must be a list of { approvers: { permission, role, team, users, manager }, required, escalateAfter, escalateTo } objects' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
    end if;
    for v_who in select a.w from (values (v_step -> 'approvers', true), (v_step -> 'escalateTo', v_step ? 'escalateTo')) a(w, checked) where a.checked loop
      if jsonb_typeof(v_who) is distinct from 'object'
        or not (v_who ?| array['permission', 'role', 'team', 'users', 'manager'])
        or (v_who ? 'manager' and v_who -> 'manager' <> 'true'::jsonb)
        or (v_who ? 'users' and (jsonb_typeof(v_who -> 'users') <> 'array'
          or exists (select 1 from jsonb_array_elements(v_who -> 'users') u
            where jsonb_typeof(u) <> 'string' or u #>> '{}' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'))) then
        raise exception 'steps must be a list of { approvers: { permission, role, team, users, manager }, required, escalateAfter, escalateTo } objects' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
      end if;
    end loop;
    if (v_step ? 'required' and v_step -> 'required' <> '"all"'::jsonb and (jsonb_typeof(v_step -> 'required') <> 'number' or (v_step ->> 'required')::numeric < 1
        or (v_step ->> 'required')::numeric <> trunc((v_step ->> 'required')::numeric)))
      or (v_step -> 'required' = '"all"'::jsonb and (v_step -> 'approvers') - 'permission' <> '{}'::jsonb
        and ((v_step -> 'approvers') - 'users' <> '{}'::jsonb or jsonb_array_length(v_step -> 'approvers' -> 'users') = 0))
      or (jsonb_typeof(v_step -> 'required') = 'number' and (v_step -> 'approvers') - 'users' = '{}'::jsonb
        and (v_step ->> 'required')::numeric > jsonb_array_length(v_step -> 'approvers' -> 'users'))
      or ((v_step ? 'escalateAfter') <> (v_step ? 'escalateTo'))
      or (v_step ? 'escalateAfter' and (jsonb_typeof(v_step -> 'escalateAfter') <> 'string' or (v_step ->> 'escalateAfter')::interval <= interval '0')) then
      raise exception 'steps must be a list of { approvers: { permission, role, team, users, manager }, required, escalateAfter, escalateTo } objects' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
    end if;
  end loop;
  v_steps := (select coalesce(jsonb_agg(case when s -> 'required' = '"all"'::jsonb and (s -> 'approvers') ? 'users'
    then jsonb_set(s, '{required}', to_jsonb(jsonb_array_length(s -> 'approvers' -> 'users'))) || '{"all": true}'::jsonb else s - 'all' end order by o), '[]'::jsonb)
    from jsonb_array_elements(v_steps) with ordinality e(s, o));
  if coalesce(save_approval_policy.policy ->> 'mode', v_old."mode"::text, 'authorize') not in ('confirm', 'authorize') then
    raise exception 'mode must be confirm or authorize' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
  end if;
  if v_old."id" is null then
    insert into "better_supabase"."approval_policies" ("tenant_id", "subject_type", "action", "name", "conditions", "effect", "mode", "steps", "self_approval", "expires_in", "enabled", "created_by", "description")
    values (save_approval_policy.tenant, v_type, v_action, btrim(save_approval_policy.policy ->> 'name'), v_conditions, v_effect,
      coalesce(save_approval_policy.policy ->> 'mode', 'authorize'), v_steps,
      coalesce((save_approval_policy.policy ->> 'selfApproval')::boolean, false), (save_approval_policy.policy ->> 'expiresIn')::interval,
      coalesce((save_approval_policy.policy ->> 'enabled')::boolean, true), auth.uid(), case when coalesce(save_approval_policy.policy -> 'fields', '{}'::jsonb) ? 'description' then (jsonb_populate_record(null::"better_supabase"."approval_policies", jsonb_build_object('description', coalesce(save_approval_policy.policy -> 'fields', '{}'::jsonb) -> 'description')))."description" else better_supabase.column_default('"better_supabase"."approval_policies"', 'description', (null::"better_supabase"."approval_policies")."description") end)
    returning * into v_row;
  else
    update "better_supabase"."approval_policies" x set
      "subject_type" = v_type,
      "action" = v_action,
      "name" = coalesce(btrim(save_approval_policy.policy ->> 'name'), x."name"),
      "conditions" = v_conditions,
      "effect" = v_effect,
      "mode" = coalesce(save_approval_policy.policy ->> 'mode', x."mode"),
      "steps" = v_steps,
      "self_approval" = coalesce((save_approval_policy.policy ->> 'selfApproval')::boolean, x."self_approval"),
      "expires_in" = case when save_approval_policy.policy ? 'expiresIn' then (save_approval_policy.policy ->> 'expiresIn')::interval else x."expires_in" end,
      "enabled" = coalesce((save_approval_policy.policy ->> 'enabled')::boolean, x."enabled"),
      "updated_at" = now(), "description" = case when (save_approval_policy.policy -> 'fields') ? 'description' then (jsonb_populate_record(null::"better_supabase"."approval_policies", jsonb_build_object('description', (save_approval_policy.policy -> 'fields') -> 'description')))."description" else x."description" end
    where x."id" = v_old."id"
    returning * into v_row;
  end if;
  if v_old."id" is null then
    perform "better_supabase".emit_event('approval_policy.created', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'subjectType', v_row."subject_type", 'action', v_row."action"), 'approval-policies/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/approvals');
  perform better_supabase.audit_event(
    event_type => 'approval_policy.created',
    category => 'configuration',
    target_type => 'approval_policy',
    record_id => v_row."id"::text,
    summary => 'created approval policy ' || v_row."name",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'subjectType', v_row."subject_type", 'action', v_row."action")
  );
  else
    perform "better_supabase".emit_event('approval_policy.updated', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'subjectType', v_row."subject_type", 'action', v_row."action"), 'approval-policies/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/approvals');
  perform better_supabase.audit_event(
    event_type => 'approval_policy.updated',
    category => 'configuration',
    target_type => 'approval_policy',
    record_id => v_row."id"::text,
    summary => 'updated approval policy ' || v_row."name",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'subjectType', v_row."subject_type", 'action', v_row."action")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'action', v_row."action", 'effect', v_row."effect", 'name', v_row."name", 'conditions', v_row."conditions", 'mode', v_row."mode", 'steps', v_row."steps", 'selfApproval', v_row."self_approval", 'expiresIn', v_row."expires_in"::text, 'enabled', v_row."enabled", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'fields', jsonb_build_object('description', v_row."description"));
exception
  when invalid_text_representation or invalid_datetime_format or not_null_violation or check_violation then
    raise exception 'policy has an invalid name, mode, expiry or flag' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_connector_server (
  tenant uuid,
  id     uuid  DEFAULT NULL::uuid,
  fields jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."connector_servers"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_connector_server.tenant, 'connectors.manage'), false)) then
    raise exception 'you may not manage connectors here' using errcode = '42501', hint = 'CONNECTOR_FORBIDDEN';
  end if;
  if jsonb_typeof(save_connector_server.fields) is distinct from 'object' then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'CONNECTOR_INVALID';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and save_connector_server.fields -> 'credential_ref' is not null and jsonb_typeof(save_connector_server.fields -> 'credential_ref') <> 'null'
    and (jsonb_typeof(save_connector_server.fields -> 'credential_ref' -> 'tenant') is distinct from 'string' or (save_connector_server.fields -> 'credential_ref' ->> 'tenant') is distinct from (save_connector_server.tenant)::text) then
    raise exception 'credential_ref must carry the tenant % that owns it', save_connector_server.tenant
      using errcode = '42501', hint = 'CREDENTIAL_REF_FOREIGN';
  end if;
  if save_connector_server.id is null then
    insert into "better_supabase"."connector_servers" ("organization_id", "name", "url", "auth_type", "credential_ref", "created_by")
    values (save_connector_server.tenant, save_connector_server.fields ->> 'name', save_connector_server.fields ->> 'url',
      coalesce(save_connector_server.fields ->> 'auth_type', 'oauth'), save_connector_server.fields -> 'credential_ref', auth.uid())
    returning * into v_row;
  else
    select * into v_row from "better_supabase"."connector_servers" x where x."id" = save_connector_server.id and x."organization_id" = save_connector_server.tenant for update;
    if not found then
      raise exception 'connector % not found', save_connector_server.id using errcode = 'P0002', hint = 'CONNECTOR_NOT_FOUND';
    end if;
  end if;
  update "better_supabase"."connector_servers" x set
    "name" = coalesce(save_connector_server.fields ->> 'name', x."name"),
    "url" = coalesce(save_connector_server.fields ->> 'url', x."url"),
    "transport" = coalesce(save_connector_server.fields ->> 'transport', x."transport"),
    "auth_type" = coalesce(save_connector_server.fields ->> 'auth_type', x."auth_type"),
    "credential_ref" = case when save_connector_server.fields ? 'credential_ref' then nullif(save_connector_server.fields -> 'credential_ref', 'null') else x."credential_ref" end,
    "scopes" = case when save_connector_server.fields ? 'scopes' then array(select jsonb_array_elements_text(save_connector_server.fields -> 'scopes')) else x."scopes" end,
    "client_metadata" = coalesce(save_connector_server.fields -> 'client_metadata', x."client_metadata"),
    "enabled" = coalesce((save_connector_server.fields ->> 'enabled')::boolean, x."enabled"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  if save_connector_server.id is null then
    perform "better_supabase".emit_event('connector.created', jsonb_build_object('organizationId', v_row."organization_id"::text, 'serverId', v_row."id", 'name', v_row."name"), 'organizations/' || v_row."organization_id"::text || '/connectors/' || v_row."id"::text, (v_row."organization_id")::text, null, 'better-supabase/connectors');
  perform better_supabase.audit_event(
    event_type => 'connector.created',
    category => 'integration',
    target_type => 'connector',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'serverId', v_row."id", 'name', v_row."name")
  );
  else
    perform "better_supabase".emit_event('connector.updated', jsonb_build_object('organizationId', v_row."organization_id"::text, 'serverId', v_row."id", 'name', v_row."name"), 'organizations/' || v_row."organization_id"::text || '/connectors/' || v_row."id"::text, (v_row."organization_id")::text, null, 'better-supabase/connectors');
  perform better_supabase.audit_event(
    event_type => 'connector.updated',
    category => 'integration',
    target_type => 'connector',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'serverId', v_row."id", 'name', v_row."name")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'name', v_row."name", 'url', v_row."url", 'transport', v_row."transport", 'auth_type', v_row."auth_type", 'credential_ref', v_row."credential_ref", 'scopes', v_row."scopes", 'client_metadata', v_row."client_metadata", 'enabled', v_row."enabled", 'created_by', v_row."created_by", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_contract_obligation (
  contract_id   uuid,
  title         text,
  due_on        date DEFAULT NULL::date,
  owner_id      uuid DEFAULT NULL::uuid,
  description   text DEFAULT NULL::text,
  obligation_id uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_contract "better_supabase"."contracts"%rowtype;
  v_row "better_supabase"."contract_obligations"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_contract from "better_supabase"."contracts" x where x."id" = save_contract_obligation.contract_id;
  if not found then
    raise exception 'contract not found' using errcode = 'P0002', hint = 'CONTRACT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_contract."tenant_id", 'contracts.write'), false)) then
    raise exception 'not allowed to change contract obligations' using errcode = '42501', hint = 'CONTRACT_FORBIDDEN';
  end if;
  if nullif(trim(save_contract_obligation.title), '') is null then
    raise exception 'an obligation needs a title' using errcode = '22023', hint = 'CONTRACT_INVALID';
  end if;
  if save_contract_obligation.owner_id is not null and not exists (select 1 from "public"."memberships" m where m."organization_id" = v_contract."tenant_id" and m."user_id" = save_contract_obligation.owner_id) then
    raise exception 'the owner must be a member of the organization' using errcode = '22023', hint = 'CONTRACT_INVALID';
  end if;
  if save_contract_obligation.obligation_id is null then
    insert into "better_supabase"."contract_obligations" ("tenant_id", "contract_id", "title", "description", "due_on", "owner_id")
    values (v_contract."tenant_id", v_contract."id", trim(save_contract_obligation.title), nullif(trim(save_contract_obligation.description), ''), save_contract_obligation.due_on, save_contract_obligation.owner_id)
    returning * into v_row;
  else
    update "better_supabase"."contract_obligations" x set "title" = trim(save_contract_obligation.title), "description" = nullif(trim(save_contract_obligation.description), ''),
      "due_on" = save_contract_obligation.due_on, "owner_id" = save_contract_obligation.owner_id, "updated_at" = now()
      where x."id" = save_contract_obligation.obligation_id and x."contract_id" = v_contract."id"
      returning * into v_row;
    if not found then
      raise exception 'obligation not found' using errcode = 'P0002', hint = 'CONTRACT_OBLIGATION_NOT_FOUND';
    end if;
  end if;
  if save_contract_obligation.obligation_id is null then
    perform "better_supabase".emit_event('contract_obligation.created', jsonb_build_object('organizationId', v_row."tenant_id", 'obligationId', v_row."id", 'contractId', v_row."contract_id", 'status', v_row."status"), 'obligations/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/contracts');
  perform better_supabase.audit_event(
    event_type => 'contract_obligation.created',
    category => 'data',
    target_type => 'obligation',
    record_id => v_row."id"::text,
    summary => 'created obligation' || ' ' || v_row."title",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'obligationId', v_row."id", 'contractId', v_row."contract_id", 'status', v_row."status")
  );
  else
    perform "better_supabase".emit_event('contract_obligation.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'obligationId', v_row."id", 'contractId', v_row."contract_id", 'status', v_row."status"), 'obligations/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/contracts');
  perform better_supabase.audit_event(
    event_type => 'contract_obligation.updated',
    category => 'data',
    target_type => 'obligation',
    record_id => v_row."id"::text,
    summary => 'updated obligation' || ' ' || v_row."title",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'obligationId', v_row."id", 'contractId', v_row."contract_id", 'status', v_row."status")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'contractId', v_row."contract_id", 'title', v_row."title", 'description', v_row."description", 'dueOn', v_row."due_on", 'ownerId', v_row."owner_id", 'status', v_row."status", 'overdue', (v_row."status" = 'open' and v_row."due_on" < current_date), 'completedAt', v_row."completed_at", 'completedBy', v_row."completed_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_control (
  framework_id uuid,
  code         text,
  title        text,
  description  text    DEFAULT NULL::text,
  owner_id     uuid    DEFAULT NULL::uuid,
  applicable   boolean DEFAULT true,
  control_id   uuid    DEFAULT NULL::uuid,
  source       text    DEFAULT NULL::text,
  jurisdiction text    DEFAULT NULL::text
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_framework."tenant_id", 'compliance.manage'), false)) then
    raise exception 'not allowed to manage controls' using errcode = '42501', hint = 'CONTROL_FORBIDDEN';
  end if;
  if nullif(trim(save_control.code), '') is null or nullif(trim(save_control.title), '') is null then
    raise exception 'a control needs a code and a title' using errcode = '22023', hint = 'CONTROL_INVALID';
  end if;
  if save_control.owner_id is not null and not exists (select 1 from "public"."memberships" m where m."organization_id" = v_framework."tenant_id" and m."user_id" = save_control.owner_id) then
    raise exception 'the owner must be a member of the organization' using errcode = '22023', hint = 'CONTROL_INVALID';
  end if;
  v_new := false;
  if save_control.control_id is null then
    v_new := not exists (select 1 from "better_supabase"."controls" x where x."framework_id" = v_framework."id" and x."code" = trim(save_control.code));
    insert into "better_supabase"."controls" ("tenant_id", "framework_id", "code", "title", "description", "owner_id", "source", "jurisdiction", "applicable")
    values (v_framework."tenant_id", v_framework."id", trim(save_control.code), trim(save_control.title), nullif(trim(save_control.description), ''), save_control.owner_id, nullif(trim(save_control.source), ''), nullif(trim(save_control.jurisdiction), ''), coalesce(save_control.applicable, true))
    on conflict ("framework_id", "code") do update
      set "title" = excluded."title", "description" = excluded."description", "source" = excluded."source", "jurisdiction" = excluded."jurisdiction",
        "owner_id" = excluded."owner_id", "applicable" = excluded."applicable", "updated_at" = now()
    returning * into v_row;
  else
    update "better_supabase"."controls" x set "code" = trim(save_control.code), "title" = trim(save_control.title),
      "description" = nullif(trim(save_control.description), ''), "source" = nullif(trim(save_control.source), ''), "jurisdiction" = nullif(trim(save_control.jurisdiction), ''), "owner_id" = save_control.owner_id,
      "applicable" = coalesce(save_control.applicable, true), "updated_at" = now()
      where x."id" = save_control.control_id and x."framework_id" = v_framework."id"
      returning * into v_row;
    if not found then
      raise exception 'control not found' using errcode = 'P0002', hint = 'CONTROL_NOT_FOUND';
    end if;
  end if;
  if v_new then
    perform "better_supabase".emit_event('control.created', jsonb_build_object('organizationId', v_row."tenant_id", 'controlId', v_row."id", 'frameworkId', v_row."framework_id", 'code', v_row."code"), 'controls/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/compliance');
  perform better_supabase.audit_event(
    event_type => 'control.created',
    category => 'data',
    target_type => 'control',
    record_id => v_row."id"::text,
    summary => 'created control ' || v_row."code",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'controlId', v_row."id", 'frameworkId', v_row."framework_id", 'code', v_row."code")
  );
  else
    perform "better_supabase".emit_event('control.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'controlId', v_row."id", 'frameworkId', v_row."framework_id", 'code', v_row."code"), 'controls/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/compliance');
  perform better_supabase.audit_event(
    event_type => 'control.updated',
    category => 'data',
    target_type => 'control',
    record_id => v_row."id"::text,
    summary => 'updated control ' || v_row."code",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'controlId', v_row."id", 'frameworkId', v_row."framework_id", 'code', v_row."code")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'frameworkId', v_row."framework_id", 'code', v_row."code", 'title', v_row."title", 'description', v_row."description", 'ownerId', v_row."owner_id", 'applicable', v_row."applicable", 'source', v_row."source", 'jurisdiction', v_row."jurisdiction", 'status', case
    when not v_row."applicable" then 'not_applicable'
    when exists (select 1 from "better_supabase"."evidence_tasks" st where st."control_id" = v_row."id" and (st."active" and st."due_on" < current_date)) then 'failing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = v_row."id" and (se."valid_until" is null or se."valid_until" >= current_date)) then 'passing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = v_row."id") then 'failing'
    else 'not_started'
  end, 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_course (
  tenant uuid,
  course jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_id uuid;
  v_old "better_supabase"."courses";
  v_row "better_supabase"."courses";
  v_key text;
  v_title text;
  v_summary text;
  v_status text;
  v_certificate boolean;
  v_valid_for integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_course.tenant is not null and coalesce(better_supabase.can('tenant', save_course.tenant, 'courses.manage'), false))) then
    raise exception 'not allowed to manage courses' using errcode = '42501', hint = 'COURSE_FORBIDDEN';
  end if;
  if save_course.course is null or jsonb_typeof(save_course.course) <> 'object' then
    raise exception 'course must be an object' using errcode = '22023', hint = 'COURSE_INVALID';
  end if;
  v_id := nullif(save_course.course ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from "better_supabase"."courses" x where x."id" = v_id and x."tenant_id" = save_course.tenant for update;
    if v_old."id" is null then
      raise exception 'course not found' using errcode = 'P0002', hint = 'COURSE_NOT_FOUND';
    end if;
  end if;
  v_key := coalesce(save_course.course ->> 'key', v_old."key");
  v_title := trim(coalesce(save_course.course ->> 'title', v_old."title"));
  v_summary := case when save_course.course ? 'summary' then nullif(trim(save_course.course ->> 'summary'), '') else v_old."summary" end;
  v_status := coalesce(save_course.course ->> 'status', v_old."status", 'draft');
  v_certificate := case when save_course.course ? 'certificate' then (save_course.course ->> 'certificate')::boolean else coalesce(v_old."issues_certificate", true) end;
  v_valid_for := v_old."valid_for_months";
  if save_course.course ? 'validForMonths' then
    if jsonb_typeof(save_course.course -> 'validForMonths') = 'null' then
      v_valid_for := null;
    elsif jsonb_typeof(save_course.course -> 'validForMonths') <> 'number'
      or (save_course.course ->> 'validForMonths')::numeric % 1 <> 0
      or (save_course.course ->> 'validForMonths')::numeric not between 1 and 240 then
      raise exception 'validForMonths must be a whole number of months from 1 to 240, or null' using errcode = '22023', hint = 'COURSE_INVALID';
    else
      v_valid_for := (save_course.course ->> 'validForMonths')::integer;
    end if;
  end if;
  if v_key is null or v_key !~ '^[a-z][a-z0-9-]{0,62}$' then
    raise exception 'key: use lowercase letters, digits or "-", starting with a letter' using errcode = '22023', hint = 'COURSE_INVALID';
  end if;
  if v_title is null or length(v_title) not between 1 and 200 then
    raise exception 'title must be 1 to 200 characters' using errcode = '22023', hint = 'COURSE_INVALID';
  end if;
  if length(v_summary) > 2000 then
    raise exception 'summary must be at most 2000 characters' using errcode = '22023', hint = 'COURSE_INVALID';
  end if;
  if v_status not in ('draft', 'published', 'archived') then
    raise exception 'status must be draft, published or archived' using errcode = '22023', hint = 'COURSE_INVALID';
  end if;
  if v_old."id" is null then
    insert into "better_supabase"."courses" ("tenant_id", "key", "title", "summary", "status", "issues_certificate", "valid_for_months", "created_by")
    values (save_course.tenant, v_key, v_title, v_summary, v_status, v_certificate, v_valid_for, auth.uid())
    on conflict ("tenant_id", "key") do nothing
    returning * into v_row;
    if v_row."id" is null then
      raise exception 'a course with this key already exists' using errcode = '23505', hint = 'COURSE_EXISTS';
    end if;
  else
    begin
      update "better_supabase"."courses" x
      set "key" = v_key, "title" = v_title, "summary" = v_summary, "status" = v_status,
        "issues_certificate" = v_certificate,
        "valid_for_months" = v_valid_for, "updated_at" = now()
      where x."id" = v_old."id"
      returning * into v_row;
    exception when unique_violation then
      raise exception 'a course with this key already exists' using errcode = '23505', hint = 'COURSE_EXISTS';
    end;
  end if;
  if v_old."id" is null then
    perform "better_supabase".emit_event('course.created', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'status', v_row."status"), 'courses/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/courses');
  perform better_supabase.audit_event(
    event_type => 'course.created',
    category => 'data',
    target_type => 'course',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'created a course',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'status', v_row."status")
  );
  else
    perform "better_supabase".emit_event('course.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'status', v_row."status"), 'courses/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/courses');
  perform better_supabase.audit_event(
    event_type => 'course.updated',
    category => 'data',
    target_type => 'course',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'updated a course',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'status', v_row."status")
  );
  end if;
  return "better_supabase"."course_json"(v_row."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_enrollment_program (
  tenant  uuid,
  program jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_id uuid;
  v_old "better_supabase"."enrollment_programs";
  v_row "better_supabase"."enrollment_programs";
  v_key text;
  v_name text;
  v_description text;
  v_types text[];
  v_steps jsonb;
  v_enabled boolean;
  v_step jsonb;
  v_ids text[] := '{}';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_enrollment_program.tenant is not null and coalesce(better_supabase.can('tenant', save_enrollment_program.tenant, 'enrollments.manage'), false))) then
    raise exception 'not allowed to manage enrollment programs' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  if save_enrollment_program.program is null or jsonb_typeof(save_enrollment_program.program) <> 'object' then
    raise exception 'program must be an object' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  v_id := nullif(save_enrollment_program.program ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from "better_supabase"."enrollment_programs" x
    where x."id" = v_id and x."tenant_id" = save_enrollment_program.tenant
    for update;
    if v_old."id" is null then
      raise exception 'enrollment program not found' using errcode = 'P0002', hint = 'ENROLLMENTS_PROGRAM_NOT_FOUND';
    end if;
    if save_enrollment_program.program ? 'version' and (save_enrollment_program.program ->> 'version')::integer is distinct from v_old."version" then
      raise exception 'the program changed since you read it' using errcode = '40001', hint = 'ENROLLMENTS_PROGRAM_CONFLICT';
    end if;
  end if;
  if save_enrollment_program.program ? 'subjectTypes' and jsonb_typeof(save_enrollment_program.program -> 'subjectTypes') <> 'array' then
    raise exception 'subjectTypes must be an array of subject types' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  v_key := coalesce(save_enrollment_program.program ->> 'key', v_old."key");
  v_name := trim(coalesce(save_enrollment_program.program ->> 'name', v_old."name"));
  v_description := case when save_enrollment_program.program ? 'description'
    then nullif(trim(save_enrollment_program.program ->> 'description'), '') else v_old."description" end;
  v_types := case when save_enrollment_program.program ? 'subjectTypes'
    then array(select t.value from jsonb_array_elements_text(save_enrollment_program.program -> 'subjectTypes') with ordinality as t(value, ord) order by t.ord)
    else coalesce(v_old."subject_types", '{}') end;
  v_steps := case when save_enrollment_program.program ? 'steps'
    then save_enrollment_program.program -> 'steps' else coalesce(v_old."steps", '[]'::jsonb) end;
  v_enabled := case when save_enrollment_program.program ? 'enabled'
    then (save_enrollment_program.program ->> 'enabled')::boolean else coalesce(v_old."enabled", true) end;
  if v_key is null or v_key !~ '^[a-z][a-z0-9_-]{0,62}$' then
    raise exception 'key: use lowercase letters, digits, "_" or "-", starting with a letter' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if v_old."id" is not null and v_key <> v_old."key" then
    raise exception 'a program''s key can''t change' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if v_name is null or length(v_name) not between 1 and 200 then
    raise exception 'name must be 1 to 200 characters' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if length(v_description) > 2000 then
    raise exception 'description must be at most 2000 characters' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if exists (select 1 from unnest(v_types) as t(value) where t.value is null or t.value !~ '^[a-z][a-z0-9_-]{0,62}$') then
    raise exception 'subjectTypes must be lower-case subject types' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if jsonb_typeof(v_steps) <> 'array' or jsonb_array_length(v_steps) = 0 then
    raise exception 'steps: pass at least one step' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if jsonb_array_length(v_steps) > 100 then
    raise exception 'a program holds at most 100 steps' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  for v_step in select t.value from jsonb_array_elements(v_steps) as t(value) loop
    if jsonb_typeof(v_step) <> 'object' or coalesce(v_step ->> 'id', '') !~ '^[a-z][a-z0-9_.-]{0,63}$' then
      raise exception 'each step needs an id of lowercase letters, digits, "_", "." or "-"' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
    end if;
    if (v_step ->> 'id') = any(v_ids) then
      raise exception 'step ids must be unique' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
    end if;
    if length(v_step ->> 'title') > 200 or length(v_step ->> 'description') > 2000 then
      raise exception 'a step title holds at most 200 characters and a description 2000' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
    end if;
    if jsonb_typeof(v_step -> 'assignee') is not null and jsonb_typeof(v_step -> 'assignee') <> 'null' then
      if jsonb_typeof(v_step -> 'assignee') <> 'object' then
        raise exception 'a step assignee is { role } with a lowercase role or { userId } with a user id' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
      end if;
      if (select count(*) from jsonb_object_keys(v_step -> 'assignee')) <> 1
        or not (coalesce(v_step -> 'assignee' ->> 'role', '') ~ '^[a-z][a-z0-9_-]{0,62}$' or coalesce(v_step -> 'assignee' ->> 'userId', '') ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') then
        raise exception 'a step assignee is { role } with a lowercase role or { userId } with a user id' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
      end if;
    end if;
    if jsonb_typeof(v_step -> 'due') is not null and jsonb_typeof(v_step -> 'due') <> 'null' then
      if jsonb_typeof(v_step -> 'due') <> 'object' then
        raise exception 'a step due date is { days, from } with whole days from -3650 to 3650 and from "start" or "end"' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
      end if;
      if exists (select 1 from jsonb_object_keys(v_step -> 'due') as k(key) where k.key not in ('days', 'from'))
        or coalesce(v_step -> 'due' ->> 'from', '') not in ('start', 'end')
        or jsonb_typeof(v_step -> 'due' -> 'days') is distinct from 'number'
        or (case when (v_step -> 'due' ->> 'days') ~ '^-?[0-9]{1,4}$' then abs((v_step -> 'due' ->> 'days')::integer) > 3650 else true end) then
        raise exception 'a step due date is { days, from } with whole days from -3650 to 3650 and from "start" or "end"' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
      end if;
    end if;
    v_ids := v_ids || (v_step ->> 'id');
  end loop;
  v_steps := (
    select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('id', t.value ->> 'id', 'title', t.value ->> 'title', 'description', t.value ->> 'description',
      'assignee', case when jsonb_typeof(t.value -> 'assignee') = 'object' then t.value -> 'assignee' end,
      'due', case when jsonb_typeof(t.value -> 'due') = 'object' then jsonb_build_object('days', (t.value -> 'due' ->> 'days')::integer, 'from', t.value -> 'due' ->> 'from') end)) order by t.ord)
    from jsonb_array_elements(v_steps) with ordinality as t(value, ord)
  );
  if v_old."id" is null then
    insert into "better_supabase"."enrollment_programs" ("tenant_id", "key", "name", "description", "subject_types", "steps", "enabled", "created_by")
    values (save_enrollment_program.tenant, v_key, v_name, v_description, v_types, v_steps, v_enabled, auth.uid())
    on conflict ("tenant_id", "key") do nothing
    returning * into v_row;
    if v_row."id" is null then
      raise exception 'a program with this key already exists' using errcode = '23505', hint = 'ENROLLMENTS_PROGRAM_EXISTS';
    end if;
  else
    update "better_supabase"."enrollment_programs" x
    set "name" = v_name, "description" = v_description, "subject_types" = v_types, "steps" = v_steps,
      "enabled" = v_enabled,
      "version" = x."version" + case when x."steps" is distinct from v_steps then 1 else 0 end,
      "updated_at" = now()
    where x."id" = v_old."id"
    returning * into v_row;
  end if;
  if v_old."id" is null then
    perform "better_supabase".emit_event('enrollment_program.created', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'version', v_row."version"), 'enrollment-programs/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/enrollments');
  perform better_supabase.audit_event(
    event_type => 'enrollment_program.created',
    category => 'data',
    target_type => 'enrollment_program',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'created an enrollment program',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'version', v_row."version")
  );
  else
    perform "better_supabase".emit_event('enrollment_program.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'version', v_row."version"), 'enrollment-programs/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/enrollments');
  perform better_supabase.audit_event(
    event_type => 'enrollment_program.updated',
    category => 'data',
    target_type => 'enrollment_program',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'updated an enrollment program',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'version', v_row."version")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'subjectTypes', to_jsonb(v_row."subject_types"), 'steps', v_row."steps", 'enabled', v_row."enabled", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_field_definition (
  tenant    uuid,
  entity    text,
  key       text,
  label     text,
  type      text,
  sensitive boolean
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_id uuid;
  v_inserted boolean;
  v_last text;
  v_rank text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_field_definition.tenant, 'custom_fields.manage'), false)) then
    raise exception 'not allowed to manage custom fields' using errcode = '42501', hint = 'FIELD_FORBIDDEN';
  end if;
  select max(d."rank" collate "C") into v_last from "better_supabase"."field_definitions" d
    where d."tenant_id" = save_field_definition.tenant and d."entity" = save_field_definition.entity;
  v_rank := case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end;
  insert into "better_supabase"."field_definitions" ("tenant_id", "entity", "key", "label", "type", "sensitive", "rank")
  values (save_field_definition.tenant, save_field_definition.entity, save_field_definition.key, save_field_definition.label, save_field_definition.type, coalesce(save_field_definition.sensitive, false), v_rank)
  on conflict ("tenant_id", "entity", "key")
  do update set "label" = excluded."label", "sensitive" = excluded."sensitive"
  returning "id", xmax = 0 into v_id, v_inserted;
  if v_inserted then
    perform "better_supabase".emit_event('field_definition.created', jsonb_build_object('organizationId', save_field_definition.tenant, 'id', v_id, 'entity', save_field_definition.entity), 'custom-fields/' || coalesce(v_id::text, save_field_definition.key), (save_field_definition.tenant)::text, null, 'better-supabase/custom-fields');
  else
    perform "better_supabase".emit_event('field_definition.updated', jsonb_build_object('organizationId', save_field_definition.tenant, 'id', v_id, 'entity', save_field_definition.entity), 'custom-fields/' || coalesce(v_id::text, save_field_definition.key), (save_field_definition.tenant)::text, null, 'better-supabase/custom-fields');
  end if;
  return jsonb_build_object('id', v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_flag (
  key        text,
  definition jsonb,
  message    text  DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  d jsonb := coalesce(definition, '{}');
  saved jsonb;
  v_inserted boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('flags.manage'), false))) then
    raise exception 'Not allowed to manage feature flags' using errcode = '42501', hint = 'FLAGS_FORBIDDEN';
  end if;
  if d ? 'rollout_variants' and jsonb_typeof(d -> 'rollout_variants') = 'array' and exists (
    select 1 from jsonb_array_elements(d -> 'rollout_variants') e
    where jsonb_typeof(e.value) <> 'object' or not (coalesce(d -> 'variants', (select x."variants" from "better_supabase"."flags" x where x."key" = save_flag.key), '{"on": true, "off": false}'::jsonb) ? (e.value ->> 'variant'))
      or coalesce((e.value ->> 'weight')::numeric, -1) not between 0 and 100
  ) then
    raise exception 'Each rollout variant needs a known variant and a weight from 0 to 100' using errcode = '22023', hint = 'FLAGS_ROLLOUT_VARIANTS';
  end if;
  v_inserted := not exists (select 1 from "better_supabase"."flags" x where x."key" = save_flag.key);
  insert into "better_supabase"."flags" as x ("key", "type", "description", "variants", "default_variant", "enabled", "archived", "rules", "rollout_percentage", "rollout_variants", "rollout_schedule")
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
    coalesce(d -> 'rollout_variants', '[]'::jsonb),
    nullif(d -> 'rollout_schedule', 'null'::jsonb)
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
    "rollout_variants" = case when d ? 'rollout_variants' then excluded."rollout_variants" else x."rollout_variants" end,
    "rollout_schedule" = case when d ? 'rollout_schedule' then excluded."rollout_schedule" else x."rollout_schedule" end,
    "updated_at" = now();
  saved := (select v from jsonb_array_elements("better_supabase"."flag_definitions"()) v where v ->> 'key' = save_flag.key);
  insert into "better_supabase"."flag_revisions" ("flag_key", "revision", "definition", "message", "changed_by")
  values (
    save_flag.key,
    coalesce((select max(h."revision") from "better_supabase"."flag_revisions" h where h."flag_key" = save_flag.key), 0) + 1,
    saved - 'overrides' - 'segments',
    save_flag.message,
    (select u.id from auth.users u where u.id = auth.uid())
  );
  if v_inserted then
    perform "better_supabase".emit_event('flag.created', jsonb_build_object('key', save_flag.key), 'flags/' || save_flag.key, null, null, 'better-supabase/flags');
  perform better_supabase.audit_event(
    event_type => 'flag.created',
    category => 'configuration',
    target_type => 'flag',
    record_id => save_flag.key,
    metadata => jsonb_build_object('key', save_flag.key)
  );
  else
    perform "better_supabase".emit_event('flag.updated', jsonb_build_object('key', save_flag.key), 'flags/' || save_flag.key, null, null, 'better-supabase/flags');
  perform better_supabase.audit_event(
    event_type => 'flag.updated',
    category => 'configuration',
    target_type => 'flag',
    record_id => save_flag.key,
    metadata => jsonb_build_object('key', save_flag.key)
  );
  end if;
  return saved;
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
      raise exception 'job not found' using errcode = 'P0002', hint = 'JOB_OPENING_NOT_FOUND';
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
    raise exception 'a job needs a title and a status of draft, open or closed' using errcode = '22023', hint = 'JOB_OPENING_INVALID';
  end;
  if v_job."status" is distinct from v_was then
    if v_job."status" = 'open' then
      update "better_supabase"."job_openings" x set "opened_at" = coalesce(x."opened_at", now()), "closed_at" = null where x."id" = v_job."id" returning * into v_job;
      perform "better_supabase".emit_event('job_opening.opened', jsonb_build_object('organizationId', v_job."tenant_id", 'jobId', v_job."id", 'title', v_job."title"), 'jobs/' || v_job."id"::text, (v_job."tenant_id"::text)::text, null, 'better-supabase/hiring');
    elsif v_job."status" = 'closed' then
      update "better_supabase"."job_openings" x set "closed_at" = now() where x."id" = v_job."id" returning * into v_job;
      perform "better_supabase".emit_event('job_opening.closed', jsonb_build_object('organizationId', v_job."tenant_id", 'jobId', v_job."id", 'title', v_job."title"), 'jobs/' || v_job."id"::text, (v_job."tenant_id"::text)::text, null, 'better-supabase/hiring');
    end if;
  end if;
  return to_jsonb(v_job);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_pipeline_stage (
  pipeline           uuid,
  stage              uuid,
  key                text,
  name               text,
  category           text,
  probability        integer,
  rotting_after_days integer,
  wip_limit          integer,
  color              text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_subject_type text;
  v_outcome text;
  v_stage uuid := save_pipeline_stage.stage;
  v_pipeline uuid := save_pipeline_stage.pipeline;
  v_used boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."subject_type" into v_tenant, v_subject_type
  from "better_supabase"."pipelines" x where x."id" = save_pipeline_stage.pipeline and x."archived_at" is null;
  if v_tenant is null then
    raise exception 'pipeline not found' using errcode = 'P0002', hint = 'PIPELINE_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'pipelines.manage'), false)) then
    raise exception 'not allowed to manage pipelines' using errcode = '42501', hint = 'PIPELINE_FORBIDDEN';
  end if;
  case v_subject_type
    when 'deal' then
      v_outcome := case save_pipeline_stage.category
      when 'open' then 'open'
      when 'won' then 'success'
      when 'lost' then 'failure'
    end;
    when 'work_item' then
      v_outcome := case save_pipeline_stage.category
      when 'triage' then 'open'
      when 'backlog' then 'open'
      when 'unstarted' then 'open'
      when 'started' then 'open'
      when 'completed' then 'success'
      when 'canceled' then 'failure'
    end;
    when 'maintenance_request' then
      v_outcome := case save_pipeline_stage.category
      when 'triage' then 'open'
      when 'backlog' then 'open'
      when 'unstarted' then 'open'
      when 'started' then 'open'
      when 'completed' then 'success'
      when 'canceled' then 'failure'
    end;
    when 'application' then
      v_outcome := case save_pipeline_stage.category
      when 'active' then 'open'
      when 'hired' then 'success'
      when 'rejected' then 'failure'
      when 'withdrawn' then 'failure'
    end;
    else
      raise exception 'this subject type has no pipeline binding' using errcode = '22023', hint = 'PIPELINE_SUBJECT_UNKNOWN';
  end case;
  if v_outcome is null then
    raise exception 'this subject type has no such category' using errcode = '22023', hint = 'PIPELINE_CATEGORY_UNKNOWN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_pipeline_stage_save"(uuid, uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text, $4::text)', v_hook::oid::regproc)
        using save_pipeline_stage.pipeline, save_pipeline_stage.stage, save_pipeline_stage.key, save_pipeline_stage.category;
    end if;
  end;
  begin
    if v_stage is null then
      insert into "better_supabase"."pipeline_stages" ("tenant_id", "pipeline_id", "key", "name", "category", "outcome", "probability", "rotting_after_days", "wip_limit", "color", "rank")
      values (v_tenant, save_pipeline_stage.pipeline, save_pipeline_stage.key, save_pipeline_stage.name, save_pipeline_stage.category, v_outcome, save_pipeline_stage.probability, save_pipeline_stage.rotting_after_days, save_pipeline_stage.wip_limit, save_pipeline_stage.color,
        case
    when (select max(x."rank" collate "C") from "better_supabase"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline) is null then 'V'
    when length(substring((select max(x."rank" collate "C") from "better_supabase"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline) from '^z*')) = length((select max(x."rank" collate "C") from "better_supabase"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline)) then (select max(x."rank" collate "C") from "better_supabase"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline) || 'V'
    else left((select max(x."rank" collate "C") from "better_supabase"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline), length(substring((select max(x."rank" collate "C") from "better_supabase"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline) from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr((select max(x."rank" collate "C") from "better_supabase"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline), length(substring((select max(x."rank" collate "C") from "better_supabase"."pipeline_stages" x where x."pipeline_id" = save_pipeline_stage.pipeline) from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end)
      returning "id" into v_stage;
    else
      -- A stage holding records keeps its outcome, so won stays won.
      if exists (select 1 from "better_supabase"."pipeline_stages" x where x."id" = v_stage and x."outcome" <> v_outcome) then
        case v_subject_type
    when 'deal' then
      perform 1 from "better_supabase"."deals" r where r."stage_id" = v_stage limit 1;
      v_used := found;
    when 'work_item' then
      perform 1 from "better_supabase"."work_items" r where r."stage_id" = v_stage limit 1;
      v_used := found;
    when 'maintenance_request' then
      perform 1 from "better_supabase"."maintenance_requests" r where r."stage_id" = v_stage limit 1;
      v_used := found;
    when 'application' then
      perform 1 from "better_supabase"."applications" r where r."stage_id" = v_stage limit 1;
      v_used := found;
    else
      v_used := false;
  end case;
        if v_used then
          raise exception 'records are in this stage; its outcome can''t change' using errcode = '23503', hint = 'PIPELINE_STAGE_IN_USE';
        end if;
      end if;
      update "better_supabase"."pipeline_stages" x set "key" = save_pipeline_stage.key, "name" = save_pipeline_stage.name, "category" = save_pipeline_stage.category, "outcome" = v_outcome, "probability" = save_pipeline_stage.probability, "rotting_after_days" = save_pipeline_stage.rotting_after_days, "wip_limit" = save_pipeline_stage.wip_limit, "color" = save_pipeline_stage.color, "updated_at" = now()
      where x."id" = v_stage and x."pipeline_id" = save_pipeline_stage.pipeline;
      if not found then
        raise exception 'stage not found' using errcode = 'P0002', hint = 'PIPELINE_STAGE_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'another stage of this pipeline has this key' using errcode = '23505', hint = 'PIPELINE_STAGE_KEY_TAKEN';
  end;
  if save_pipeline_stage.stage is null then
    perform "better_supabase".emit_event('pipeline_stage.created', jsonb_build_object('organizationId', v_tenant, 'pipelineId', v_pipeline, 'stageId', v_stage, 'key', save_pipeline_stage.key, 'category', save_pipeline_stage.category), 'pipelines/' || v_pipeline::text, (v_tenant::text)::text, null, 'better-supabase/pipelines');
  perform better_supabase.audit_event(
    event_type => 'pipeline_stage.created',
    category => 'configuration',
    target_type => 'pipeline',
    record_id => v_pipeline::text,
    summary => 'created stage ' || save_pipeline_stage.name,
    tenant => (v_tenant::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'pipelineId', v_pipeline, 'stageId', v_stage, 'key', save_pipeline_stage.key, 'category', save_pipeline_stage.category)
  );
  else
    perform "better_supabase".emit_event('pipeline_stage.updated', jsonb_build_object('organizationId', v_tenant, 'pipelineId', v_pipeline, 'stageId', v_stage, 'key', save_pipeline_stage.key, 'category', save_pipeline_stage.category), 'pipelines/' || v_pipeline::text, (v_tenant::text)::text, null, 'better-supabase/pipelines');
  perform better_supabase.audit_event(
    event_type => 'pipeline_stage.updated',
    category => 'configuration',
    target_type => 'pipeline',
    record_id => v_pipeline::text,
    summary => 'updated stage ' || save_pipeline_stage.name,
    tenant => (v_tenant::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'pipelineId', v_pipeline, 'stageId', v_stage, 'key', save_pipeline_stage.key, 'category', save_pipeline_stage.category)
  );
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_pipeline_stage_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_stage;
    end if;
  end;
  return (select to_jsonb(x) from "better_supabase"."pipeline_stages" x where x."id" = v_stage);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_post_board (
  tenant uuid,
  board  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_id uuid;
  v_old "better_supabase"."post_boards";
  v_row "better_supabase"."post_boards";
  v_key text;
  v_name text;
  v_kind text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_post_board.tenant is not null and coalesce(better_supabase.can('tenant', save_post_board.tenant, 'posts.manage'), false))) then
    raise exception 'not allowed to manage boards' using errcode = '42501', hint = 'POST_FORBIDDEN';
  end if;
  if jsonb_typeof(save_post_board.board) is distinct from 'object' then
    raise exception 'board must be an object' using errcode = '22023', hint = 'POST_INVALID';
  end if;
  v_id := nullif(save_post_board.board ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from "better_supabase"."post_boards" x where x."id" = v_id and x."tenant_id" = save_post_board.tenant for update;
    if v_old."id" is null then
      raise exception 'no such board' using errcode = 'P0002', hint = 'POST_BOARD_NOT_FOUND';
    end if;
    if save_post_board.board ? 'key' and save_post_board.board ->> 'key' is distinct from v_old."key" then
      raise exception 'a board''s key can''t change' using errcode = '22023', hint = 'POST_INVALID';
    end if;
  end if;
  v_key := coalesce(v_old."key", save_post_board.board ->> 'key');
  v_name := coalesce(nullif(trim(save_post_board.board ->> 'name'), ''), v_old."name");
  v_kind := coalesce(save_post_board.board ->> 'kind', v_old."kind", 'forum');
  if v_key is null or v_key !~ '^[a-z0-9][a-z0-9_-]{0,62}$' then
    raise exception 'a board needs a key of lowercase letters, digits, dashes and underscores' using errcode = '22023', hint = 'POST_INVALID';
  end if;
  if v_name is null or length(v_name) > 200 then
    raise exception 'a board needs a name of at most 200 characters' using errcode = '22023', hint = 'POST_INVALID';
  end if;
  if v_kind not in ('forum', 'feedback') then
    raise exception 'a board''s kind is forum or feedback' using errcode = '22023', hint = 'POST_INVALID';
  end if;
  if v_old."id" is null then
    insert into "better_supabase"."post_boards" ("tenant_id", "key", "name", "description", "kind", "archived_at", "created_by")
    values (save_post_board.tenant, v_key, v_name, nullif(trim(save_post_board.board ->> 'description'), ''), v_kind,
      case when coalesce((save_post_board.board ->> 'archived')::boolean, false) then now() end, auth.uid())
    returning * into v_row;
  else
    update "better_supabase"."post_boards" x set
      "name" = v_name,
      "description" = case when save_post_board.board ? 'description' then nullif(trim(save_post_board.board ->> 'description'), '') else x."description" end,
      "kind" = v_kind,
      "archived_at" = case when save_post_board.board ? 'archived' then case when (save_post_board.board ->> 'archived')::boolean then coalesce(x."archived_at", now()) end else x."archived_at" end,
      "updated_at" = now()
    where x."id" = v_old."id"
    returning * into v_row;
  end if;
  if v_old."id" is null then
    perform "better_supabase".emit_event('post_board.created', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'kind', v_row."kind"), 'post-boards/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/posts');
  perform better_supabase.audit_event(
    event_type => 'post_board.created',
    category => 'data',
    target_type => 'post_board',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'created a board',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'kind', v_row."kind")
  );
  else
    perform "better_supabase".emit_event('post_board.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'kind', v_row."kind"), 'post-boards/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/posts');
  perform better_supabase.audit_event(
    event_type => 'post_board.updated',
    category => 'data',
    target_type => 'post_board',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'updated a board',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'kind', v_row."kind")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'kind', v_row."kind", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_product_option (
  product       uuid,
  option        uuid,
  name          text,
  option_values text[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_id uuid := save_product_option.option;
  v_last text;
  v_rank text;
  v_value text;
  v_variant uuid;
  v_new boolean := save_product_option.option is null;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."products" x where x."id" = save_product_option.product for update;
  if v_tenant is null then
    raise exception 'product not found' using errcode = 'P0002', hint = 'CATALOG_PRODUCT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  if coalesce(cardinality(save_product_option.option_values), 0) = 0 then
    raise exception 'an option needs at least one value' using errcode = '22023', hint = 'CATALOG_OPTION_EMPTY';
  end if;
  if (select count(distinct x) from unnest(save_product_option.option_values) x) <> cardinality(save_product_option.option_values) then
    raise exception 'an option lists the same value twice' using errcode = '22023', hint = 'CATALOG_OPTION_DUPLICATE';
  end if;
  begin
    if v_id is null then
      select max(x."rank" collate "C") into v_last from "better_supabase"."product_options" x where x."product_id" = save_product_option.product;
      insert into "better_supabase"."product_options" ("tenant_id", "product_id", "name", "rank")
      values (v_tenant, save_product_option.product, save_product_option.name, case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end)
      returning "id" into v_id;
    else
      update "better_supabase"."product_options" x set "name" = save_product_option.name
      where x."id" = save_product_option.option and x."product_id" = save_product_option.product;
      if not found then
        raise exception 'option not found' using errcode = 'P0002', hint = 'CATALOG_OPTION_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'the product has another option with this name' using errcode = '23505', hint = 'CATALOG_OPTION_TAKEN';
  end;
  for v_variant in
    select distinct x."variant_id" from "better_supabase"."product_variant_values" x
    join "better_supabase"."product_option_values" y on y."id" = x."option_value_id"
    where y."option_id" = v_id and not (y."value" = any (save_product_option.option_values))
  loop
    if exists (select 1 from "better_supabase"."ledger_accounts" sa where sa."managed_by" = 'inventory' and sa."kind" = 'stock' and (case when sa."kind" = 'stock' then (sa."metadata" ->> 'variantId')::uuid end) = v_variant) then
      raise exception 'a variant this list removes is still in use' using errcode = '23503', hint = 'CATALOG_OPTION_VALUE_IN_USE';
      continue;
    end if;
    begin
      delete from "better_supabase"."product_variants" x where x."id" = v_variant;
      perform "better_supabase".emit_event('product_variant.deleted', jsonb_build_object('organizationId', v_tenant, 'id', v_variant, 'productId', save_product_option.product), 'variants/' || v_variant::text, (v_tenant)::text, null, 'better-supabase/catalog');
    exception when foreign_key_violation then
      raise exception 'a variant this list removes is still in use' using errcode = '23503', hint = 'CATALOG_OPTION_VALUE_IN_USE';
    end;
  end loop;
  begin
    delete from "better_supabase"."product_option_values" x where x."option_id" = v_id and not (x."value" = any (save_product_option.option_values));
  exception when foreign_key_violation then
    raise exception 'a variant uses a value this list removes' using errcode = '23503', hint = 'CATALOG_OPTION_VALUE_IN_USE';
  end;
  v_rank := null;
  foreach v_value in array save_product_option.option_values loop
    v_rank := case
    when v_rank is null then 'V'
    when length(substring(v_rank from '^z*')) = length(v_rank) then v_rank || 'V'
    else left(v_rank, length(substring(v_rank from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_rank, length(substring(v_rank from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end;
    update "better_supabase"."product_option_values" x set "rank" = v_rank where x."option_id" = v_id and x."value" = v_value;
    if not found then
      insert into "better_supabase"."product_option_values" ("tenant_id", "option_id", "value", "rank")
      values (v_tenant, v_id, v_value, v_rank);
    end if;
  end loop;
  if v_new then
    insert into "better_supabase"."product_variant_values" ("tenant_id", "variant_id", "option_value_id")
    select v_tenant, x."id", (select y."id" from "better_supabase"."product_option_values" y where y."option_id" = v_id and y."value" = save_product_option.option_values[1])
    from "better_supabase"."product_variants" x where x."product_id" = save_product_option.product;
  end if;
  return jsonb_build_object(
    'id', v_id,
    'values', (select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'value', x."value") order by x."rank" collate "C"), '[]'::jsonb) from "better_supabase"."product_option_values" x where x."option_id" = v_id)
  );
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
    raise exception 'rule must be an object' using errcode = '22023', hint = 'AUTOMATION_INVALID';
  end if;
  v_id := nullif(rule ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from "better_supabase"."rules" x where x."id" = v_id and x."organization_id" = save_rule.tenant for update;
    if v_old."id" is null then
      raise exception 'No rule in this organization has this id' using errcode = 'P0002', hint = 'AUTOMATION_NOT_FOUND';
    end if;
    if rule ? 'version' and (rule ->> 'version')::integer is distinct from v_old."version" then
      raise exception 'The rule changed since it was read' using errcode = '40001', hint = 'AUTOMATION_CONFLICT';
    end if;
    if rule ? 'subjectType' and rule ->> 'subjectType' is distinct from v_old."subject_type" then
      raise exception 'A rule''s subject type can''t change' using errcode = '22023', hint = 'AUTOMATION_INVALID';
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (case when (v_enabled or coalesce(v_old."enabled", false)) then coalesce(better_supabase.can('tenant', save_rule.tenant, 'automations.publish'), false) else coalesce(better_supabase.can('tenant', save_rule.tenant, 'automations.write'), false) end)) then
    raise exception 'You need % to save this rule', case when (v_enabled or coalesce(v_old."enabled", false)) then '''automations.publish''' else '''automations.write''' end using errcode = '42501', hint = 'AUTOMATION_FORBIDDEN';
  end if;
  if v_subject_type is null or v_subject_type !~ '^[a-z][a-z0-9_-]{0,62}$' then
    raise exception 'A rule needs a subject type' using errcode = '22023', hint = 'AUTOMATION_INVALID';
  end if;
  if v_trigger is null or length(v_trigger) > 128 or v_trigger !~ '^[a-z][a-z0-9_]*([.:][a-z0-9_]+)*$' then
    raise exception 'A rule needs a trigger such as expense.submitted' using errcode = '22023', hint = 'AUTOMATION_INVALID';
  end if;
  if v_name is null or length(v_name) > 200 then
    raise exception 'A rule needs a name of at most 200 characters' using errcode = '22023', hint = 'AUTOMATION_INVALID';
  end if;
  v_fields := "better_supabase"."rule_field_map"(v_subject_type);
  if v_fields = '{}'::jsonb and v_old."default_key" is null then
    raise exception 'No rule fields for %; sync them first', v_subject_type using errcode = '22023', hint = 'RULE_SUBJECT_UNKNOWN';
  end if;
  perform "better_supabase"."rule_check"(v_conditions, v_fields, 1);
  if jsonb_typeof(v_actions) is distinct from 'array' or jsonb_array_length(v_actions) > 20 then
    raise exception 'actions must be an array of at most 20 entries' using errcode = '22023', hint = 'AUTOMATION_ACTIONS_INVALID';
  end if;
  for v_action in select x.value from jsonb_array_elements(v_actions) x loop
    if jsonb_typeof(v_action) is distinct from 'object' or v_action ->> 'kind' is null
      or length(v_action ->> 'kind') > 128 or v_action ->> 'kind' !~ '^[a-z][a-z0-9_]*([.][a-z0-9_]+)*$'
      or (v_action ? 'config' and jsonb_typeof(v_action -> 'config') is distinct from 'object') then
      raise exception 'Every action needs a kind such as approvals.request and an optional config object' using errcode = '22023', hint = 'AUTOMATION_ACTIONS_INVALID';
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
    return jsonb_build_object('id', v_old."id", 'organizationId', v_old."organization_id", 'subjectType', v_old."subject_type", 'trigger', v_old."trigger", 'name', v_old."name", 'description', v_old."description", 'conditions', v_old."conditions", 'actions', v_old."actions", 'enabled', v_old."enabled", 'stopProcessing', v_old."stop_processing", 'rank', v_old."rank", 'version', v_old."version", 'createdBy', v_old."created_by", 'updatedBy', v_old."updated_by", 'createdAt', v_old."created_at", 'updatedAt', v_old."updated_at", 'defaultKey', v_old."default_key");
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
  if v_old."id" is null then
    perform "better_supabase".emit_event('automation.created', jsonb_build_object('organizationId', v_row."organization_id"::text, 'ruleId', v_row."id"::text, 'name', v_row."name", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'version', v_row."version"), 'rules/' || v_row."id"::text, (v_row."organization_id")::text, null, 'better-supabase/automations');
  perform better_supabase.audit_event(
    event_type => 'automation.created',
    category => 'configuration',
    target_type => 'rule',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'ruleId', v_row."id"::text, 'name', v_row."name", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'version', v_row."version"),
    actor_id => auth.uid()
  );
  else
    perform "better_supabase".emit_event('automation.updated', jsonb_build_object('organizationId', v_row."organization_id"::text, 'ruleId', v_row."id"::text, 'name', v_row."name", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'version', v_row."version"), 'rules/' || v_row."id"::text, (v_row."organization_id")::text, null, 'better-supabase/automations');
  perform better_supabase.audit_event(
    event_type => 'automation.updated',
    category => 'configuration',
    target_type => 'rule',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'ruleId', v_row."id"::text, 'name', v_row."name", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'version', v_row."version"),
    actor_id => auth.uid()
  );
  end if;
  if v_row."enabled" and not coalesce(v_old."enabled", false) then
    perform "better_supabase".emit_event('automation.enabled', jsonb_build_object('organizationId', v_row."organization_id"::text, 'ruleId', v_row."id"::text, 'name', v_row."name", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'version', v_row."version"), 'rules/' || v_row."id"::text, (v_row."organization_id")::text, null, 'better-supabase/automations');
  perform better_supabase.audit_event(
    event_type => 'automation.enabled',
    category => 'configuration',
    target_type => 'rule',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'ruleId', v_row."id"::text, 'name', v_row."name", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'version', v_row."version"),
    actor_id => auth.uid()
  );
  elsif not v_row."enabled" and coalesce(v_old."enabled", false) then
    perform "better_supabase".emit_event('automation.disabled', jsonb_build_object('organizationId', v_row."organization_id"::text, 'ruleId', v_row."id"::text, 'name', v_row."name", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'version', v_row."version"), 'rules/' || v_row."id"::text, (v_row."organization_id")::text, null, 'better-supabase/automations');
  perform better_supabase.audit_event(
    event_type => 'automation.disabled',
    category => 'configuration',
    target_type => 'rule',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'ruleId', v_row."id"::text, 'name', v_row."name", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'version', v_row."version"),
    actor_id => auth.uid()
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."organization_id", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'name', v_row."name", 'description', v_row."description", 'conditions', v_row."conditions", 'actions', v_row."actions", 'enabled', v_row."enabled", 'stopProcessing', v_row."stop_processing", 'rank', v_row."rank", 'version', v_row."version", 'createdBy', v_row."created_by", 'updatedBy', v_row."updated_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'defaultKey', v_row."default_key");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_score_model (
  tenant uuid,
  model  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_id uuid;
  v_old "better_supabase"."score_models";
  v_row "better_supabase"."score_models";
  v_key text;
  v_name text;
  v_description text;
  v_subject_type text;
  v_rules jsonb;
  v_metrics jsonb;
  v_bands jsonb;
  v_enabled boolean;
  v_fields jsonb;
  v_entry jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_score_model.tenant, 'scores.manage'), false)) then
    raise exception 'not allowed to manage score models' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  if jsonb_typeof(model) is distinct from 'object' then
    raise exception 'model must be an object' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  v_id := nullif(model ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from "better_supabase"."score_models" x where x."id" = v_id and x."tenant_id" = save_score_model.tenant for update;
    if v_old."id" is null then
      raise exception 'score model not found' using errcode = 'P0002', hint = 'SCORES_MODEL_NOT_FOUND';
    end if;
    if model ? 'version' and (model ->> 'version')::integer is distinct from v_old."version" then
      raise exception 'the score model changed since it was read' using errcode = '40001', hint = 'SCORES_MODEL_CONFLICT';
    end if;
    if model ? 'subjectType' and model ->> 'subjectType' is distinct from v_old."subject_type" then
      raise exception 'a score model''s subject type can''t change' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
    end if;
  end if;
  v_key := coalesce(v_old."key", model ->> 'key');
  v_name := coalesce(nullif(trim(model ->> 'name'), ''), v_old."name");
  v_description := case when model ? 'description' then nullif(trim(model ->> 'description'), '') else v_old."description" end;
  v_subject_type := coalesce(v_old."subject_type", model ->> 'subjectType');
  v_rules := coalesce(model -> 'rules', v_old."rules", '[]'::jsonb);
  v_metrics := coalesce(model -> 'metrics', v_old."metrics", '[]'::jsonb);
  v_bands := coalesce(model -> 'bands', v_old."bands", '[]'::jsonb);
  v_enabled := coalesce((model ->> 'enabled')::boolean, v_old."enabled", true);
  if v_key is null or v_key !~ '^[a-z][a-z0-9_-]{0,62}$' then
    raise exception 'a score model needs a key such as lead or health' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if v_name is null or length(v_name) > 200 then
    raise exception 'a score model needs a name of at most 200 characters' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if v_subject_type is null or v_subject_type !~ '^[a-z][a-z0-9_-]{0,62}$' then
    raise exception 'a score model needs a subject type' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if jsonb_typeof(v_rules) is distinct from 'array' or jsonb_array_length(v_rules) > 100 then
    raise exception 'rules must be an array of at most 100 entries' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if jsonb_typeof(v_metrics) is distinct from 'array' or jsonb_array_length(v_metrics) > 50 then
    raise exception 'metrics must be an array of at most 50 entries' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if jsonb_typeof(v_bands) is distinct from 'array' or jsonb_array_length(v_bands) > 10 then
    raise exception 'bands must be an array of at most 10 entries' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  v_fields := "better_supabase"."rule_field_map"(v_subject_type);
  for v_entry in select x.value from jsonb_array_elements(v_rules) x loop
    if jsonb_typeof(v_entry) is distinct from 'object' or coalesce(length(v_entry ->> 'id'), 0) not between 1 and 64
      or jsonb_typeof(v_entry -> 'points') is distinct from 'number'
      or jsonb_typeof(v_entry -> 'conditions') is distinct from 'object' then
      raise exception 'every rule needs an id, conditions and a number of points' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
    end if;
    if v_fields = '{}'::jsonb then
      raise exception 'no rule fields for this subject type; sync them first' using errcode = '22023', hint = 'SCORES_SUBJECT_UNKNOWN';
    end if;
    perform "better_supabase"."rule_check"(v_entry -> 'conditions', v_fields, 1);
  end loop;
  for v_entry in select x.value from jsonb_array_elements(v_metrics) x loop
    if jsonb_typeof(v_entry) is distinct from 'object' or coalesce(length(v_entry ->> 'id'), 0) not between 1 and 64
      or coalesce(v_entry ->> 'source', 'field') not in ('field', 'votes')
      or (v_entry ? 'weight' and jsonb_typeof(v_entry -> 'weight') is distinct from 'number')
      or (v_entry ? 'cap' and (jsonb_typeof(v_entry -> 'cap') is distinct from 'number' or (v_entry ->> 'cap')::numeric < 0)) then
      raise exception 'every metric needs an id, a source (field or votes), and a numeric weight and cap' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
    end if;
    if coalesce(v_entry ->> 'source', 'field') = 'field'
      and (v_fields -> (v_entry ->> 'field')) ->> 'type' is distinct from 'number' then
      raise exception 'a field metric names a number field of the subject type' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
    end if;
  end loop;
  for v_entry in select x.value from jsonb_array_elements(v_bands) x loop
    if jsonb_typeof(v_entry) is distinct from 'object' or coalesce(length(v_entry ->> 'label'), 0) not between 1 and 60
      or jsonb_typeof(v_entry -> 'min') is distinct from 'number' then
      raise exception 'every band needs a label and a min score' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
    end if;
  end loop;
  v_bands := coalesce((
    select jsonb_agg(jsonb_build_object('label', x.value ->> 'label', 'min', (x.value ->> 'min')::numeric) order by (x.value ->> 'min')::numeric desc)
    from jsonb_array_elements(v_bands) x
  ), '[]'::jsonb);
  if v_old."id" is null then
    if exists (select 1 from "better_supabase"."score_models" x where x."tenant_id" = save_score_model.tenant and x."key" = v_key) then
      raise exception 'a score model with this key already exists' using errcode = '23505', hint = 'SCORES_MODEL_KEY_TAKEN';
    end if;
    insert into "better_supabase"."score_models" ("tenant_id", "key", "name", "description", "subject_type", "rules", "metrics", "bands", "enabled", "created_by")
    values (save_score_model.tenant, v_key, v_name, v_description, v_subject_type, v_rules, v_metrics, v_bands, v_enabled, auth.uid())
    returning * into v_row;
  elsif v_old."name" = v_name and v_old."description" is not distinct from v_description
    and v_old."rules" = v_rules and v_old."metrics" = v_metrics
    and v_old."bands" = v_bands and v_old."enabled" = v_enabled then
    return jsonb_build_object('id', v_old."id", 'organizationId', v_old."tenant_id", 'key', v_old."key", 'name', v_old."name", 'description', v_old."description", 'subjectType', v_old."subject_type", 'rules', v_old."rules", 'metrics', v_old."metrics", 'bands', v_old."bands", 'enabled', v_old."enabled", 'version', v_old."version", 'createdBy', v_old."created_by", 'createdAt', v_old."created_at", 'updatedAt', v_old."updated_at");
  else
    update "better_supabase"."score_models" x set
      "name" = v_name,
      "description" = v_description,
      "rules" = v_rules,
      "metrics" = v_metrics,
      "bands" = v_bands,
      "enabled" = v_enabled,
      "version" = x."version" + case when x."rules" = v_rules and x."metrics" = v_metrics and x."bands" = v_bands then 0 else 1 end,
      "updated_at" = now()
    where x."id" = v_old."id"
    returning * into v_row;
  end if;
  insert into "better_supabase"."score_model_versions" ("model_id", "version", "tenant_id", "rules", "metrics", "bands", "saved_by")
  values (v_row."id", v_row."version", v_row."tenant_id", v_row."rules", v_row."metrics", v_row."bands", auth.uid())
  on conflict do nothing;
  if v_old."id" is null then
    perform "better_supabase".emit_event('score_model.created', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'subjectType', v_row."subject_type", 'version', v_row."version"), 'score-models/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/scores');
  perform better_supabase.audit_event(
    event_type => 'score_model.created',
    category => 'data',
    target_type => 'score_model',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'created score model',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'subjectType', v_row."subject_type", 'version', v_row."version")
  );
  else
    perform "better_supabase".emit_event('score_model.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'subjectType', v_row."subject_type", 'version', v_row."version"), 'score-models/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/scores');
  perform better_supabase.audit_event(
    event_type => 'score_model.updated',
    category => 'data',
    target_type => 'score_model',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'updated score model',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'subjectType', v_row."subject_type", 'version', v_row."version")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'subjectType', v_row."subject_type", 'rules', v_row."rules", 'metrics', v_row."metrics", 'bands', v_row."bands", 'enabled', v_row."enabled", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_segment (
  tenant  uuid,
  segment jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid;
  v_old "better_supabase"."segments";
  v_row "better_supabase"."segments";
  v_type text;
  v_name text;
  v_description text;
  v_conditions jsonb;
  v_fields jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not coalesce(better_supabase.can('tenant', save_segment.tenant, 'segments.write'), false) then
    raise exception 'You need segments.edit to save a segment' using errcode = '42501', hint = 'SEGMENT_FORBIDDEN';
  end if;
  if jsonb_typeof(segment) is distinct from 'object' then
    raise exception 'segment must be an object' using errcode = '22023', hint = 'SEGMENT_INVALID';
  end if;
  v_id := nullif(segment ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from "better_supabase"."segments" x
    where x."id" = v_id and x."tenant_id" = save_segment.tenant for update;
    if v_old."id" is null then
      raise exception 'No segment in this organization has this id' using errcode = 'P0002', hint = 'SEGMENT_NOT_FOUND';
    end if;
    if segment ? 'subjectType' and segment ->> 'subjectType' is distinct from v_old."subject_type" then
      raise exception 'A segment''s subject type can''t change' using errcode = '22023', hint = 'SEGMENT_INVALID';
    end if;
  end if;
  v_type := coalesce(v_old."subject_type", segment ->> 'subjectType');
  if v_type is null or v_type not in ('message', 'conversation', 'channel', 'company', 'person', 'deal', 'course', 'post', 'activity', 'quote', 'work_item', 'employee', 'invoice', 'ledger_account', 'product', 'product_variant', 'order', 'calendar_event', 'booking', 'asset', 'asset_location', 'lease', 'expense_report', 'expense_line', 'donation_fund', 'work_order', 'shipment', 'contract', 'control', 'compliance_policy', 'qualification_type', 'risk', 'care_plan', 'incident', 'content_entry', 'form', 'document', 'customer', 'drive_node', 'application', 'change_request', 'project', 'task') then
    raise exception 'subjectType must be a type in config.subjects' using errcode = '22023', hint = 'SEGMENT_SUBJECT_UNKNOWN';
  end if;
  v_name := coalesce(nullif(trim(segment ->> 'name'), ''), v_old."name");
  if v_name is null or length(v_name) > 200 then
    raise exception 'A segment needs a name of at most 200 characters' using errcode = '22023', hint = 'SEGMENT_INVALID';
  end if;
  v_description := case when segment ? 'description' then nullif(trim(segment ->> 'description'), '') else v_old."description" end;
  v_conditions := coalesce(segment -> 'conditions', v_old."conditions");
  if jsonb_typeof(v_conditions) is distinct from 'object' then
    raise exception 'A segment needs conditions, a filter tree' using errcode = '22023', hint = 'SEGMENT_INVALID';
  end if;
  v_fields := "better_supabase"."rule_field_map"(v_type);
  if v_fields = '{}'::jsonb then
    raise exception 'No rule fields for this subject type; sync them first' using errcode = '22023', hint = 'SEGMENT_FIELDS_MISSING';
  end if;
  perform "better_supabase"."rule_check"(v_conditions, v_fields, 1);
  if v_old."id" is null then
    insert into "better_supabase"."segments" ("tenant_id", "name", "description", "subject_type", "conditions", "created_by")
    values (save_segment.tenant, v_name, v_description, v_type, v_conditions, auth.uid())
    returning * into v_row;
  elsif v_old."name" = v_name and v_old."description" is not distinct from v_description
    and v_old."conditions" = v_conditions then
    return jsonb_build_object('id', v_old."id", 'organizationId', v_old."tenant_id", 'name', v_old."name", 'description', v_old."description", 'subjectType', v_old."subject_type", 'conditions', v_old."conditions", 'memberCount', v_old."member_count", 'refreshedAt', v_old."refreshed_at", 'createdBy', v_old."created_by", 'createdAt', v_old."created_at", 'updatedAt', v_old."updated_at");
  else
    update "better_supabase"."segments" x set
      "name" = v_name,
      "description" = v_description,
      "conditions" = v_conditions,
      "refreshed_at" = case when x."conditions" = v_conditions then x."refreshed_at" end,
      "updated_at" = now()
    where x."id" = v_old."id"
    returning * into v_row;
  end if;
  if v_old."id" is null then
    perform "better_supabase".emit_event('segment.created', jsonb_build_object('organizationId', v_row."tenant_id", 'segmentId', v_row."id", 'subjectType', v_row."subject_type", 'name', v_row."name"), 'segments/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/segments');
  perform better_supabase.audit_event(
    event_type => 'segment.created',
    category => 'data',
    target_type => 'segment',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."tenant_id"::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'segmentId', v_row."id", 'subjectType', v_row."subject_type", 'name', v_row."name")
  );
  else
    perform "better_supabase".emit_event('segment.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'segmentId', v_row."id", 'subjectType', v_row."subject_type", 'name', v_row."name"), 'segments/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/segments');
  perform better_supabase.audit_event(
    event_type => 'segment.updated',
    category => 'data',
    target_type => 'segment',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."tenant_id"::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'segmentId', v_row."id", 'subjectType', v_row."subject_type", 'name', v_row."name")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'description', v_row."description", 'subjectType', v_row."subject_type", 'conditions', v_row."conditions", 'memberCount', v_row."member_count", 'refreshedAt', v_row."refreshed_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
exception when unique_violation then
  raise exception 'Another segment in this organization has this name' using errcode = '23505', hint = 'SEGMENT_NAME_TAKEN';
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_sequence (
  tenant   uuid,
  sequence jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_id uuid;
  v_old "better_supabase"."sequences";
  v_row "better_supabase"."sequences";
  v_key text;
  v_name text;
  v_description text;
  v_status text;
  v_exit boolean;
  v_account uuid;
  v_steps jsonb;
  v_member "better_supabase"."sequence_enrollments";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_sequence.tenant is not null and coalesce(better_supabase.can('tenant', save_sequence.tenant, 'sequences.manage'), false))) then
    raise exception 'not allowed to manage sequences' using errcode = '42501', hint = 'SEQUENCE_FORBIDDEN';
  end if;
  if save_sequence.sequence is null or jsonb_typeof(save_sequence.sequence) <> 'object' then
    raise exception 'sequence must be an object' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  v_id := nullif(save_sequence.sequence ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from "better_supabase"."sequences" x
    where x."id" = v_id and x."tenant_id" = save_sequence.tenant
    for update;
    if v_old."id" is null then
      raise exception 'sequence not found' using errcode = 'P0002', hint = 'SEQUENCE_NOT_FOUND';
    end if;
  end if;
  v_key := coalesce(save_sequence.sequence ->> 'key', v_old."key");
  v_name := trim(coalesce(save_sequence.sequence ->> 'name', v_old."name"));
  v_description := case when save_sequence.sequence ? 'description'
    then nullif(trim(save_sequence.sequence ->> 'description'), '') else v_old."description" end;
  v_status := coalesce(save_sequence.sequence ->> 'status', v_old."status"::text, 'draft');
  v_exit := case when save_sequence.sequence ? 'exitOnReply'
    then (save_sequence.sequence ->> 'exitOnReply')::boolean else coalesce(v_old."exit_on_reply", true) end;
  v_account := case when save_sequence.sequence ? 'accountId'
    then nullif(save_sequence.sequence ->> 'accountId', '')::uuid else v_old."mail_account_id" end;
  v_steps := case when save_sequence.sequence ? 'steps'
    then save_sequence.sequence -> 'steps' else coalesce(v_old."steps", '[]'::jsonb) end;
  if v_key is null or v_key !~ '^[a-z][a-z0-9-]{0,62}$' then
    raise exception 'key: use lowercase letters, digits or "-", starting with a letter' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if v_old."id" is not null and v_key <> v_old."key" then
    raise exception 'a sequence''s key can''t change' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if v_name is null or length(v_name) not between 1 and 200 then
    raise exception 'name must be 1 to 200 characters' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if length(v_description) > 2000 then
    raise exception 'description must be at most 2000 characters' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if v_status not in ('draft', 'active', 'paused', 'archived') then
    raise exception 'status must be draft, active, paused or archived' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if v_exit is null then
    raise exception 'exitOnReply must be true or false' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  perform "better_supabase"."sequence_steps_check"(v_steps, true);
  if v_status = 'active' and jsonb_array_length(v_steps) = 0 then
    raise exception 'an active sequence needs at least one step' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if v_account is not null and not exists (
    select 1 from "better_supabase"."mail_accounts" k
    where k."id" = v_account and k."tenant_id" = save_sequence.tenant
      and k."status" <> 'disconnected'
  ) then
    raise exception 'accountId must be a connected mailbox of this organization' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if v_old."id" is null then
    insert into "better_supabase"."sequences" ("tenant_id", "key", "name", "description", "status", "exit_on_reply", "mail_account_id", "steps", "version", "created_by")
    values (save_sequence.tenant, v_key, v_name, v_description, v_status, v_exit, v_account, v_steps, 1, auth.uid())
    returning * into v_row;
  else
    update "better_supabase"."sequences" x
    set "name" = v_name, "description" = v_description, "status" = v_status, "exit_on_reply" = v_exit,
      "mail_account_id" = v_account, "steps" = v_steps,
      "version" = x."version" + case when x."steps" is distinct from v_steps then 1 else 0 end,
      "updated_at" = now()
    where x."id" = v_old."id"
    returning * into v_row;
    if v_old."steps" is distinct from v_row."steps" then
      perform "better_supabase"."sequence_resync"(v_row."id");
    end if;
    if v_row."status" = 'archived' and v_old."status" <> 'archived' then
      for v_member in
        select * from "better_supabase"."sequence_enrollments" x
        where x."sequence_id" = v_row."id" and x."status" in ('active', 'paused')
      loop
        perform "better_supabase"."sequence_exit"(v_member."enrollment_id", 'archived');
      end loop;
    end if;
  end if;
  if v_old."id" is null then
    perform "better_supabase".emit_event('sequence.created', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'status', v_row."status"), 'sequences/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/sequences');
  perform better_supabase.audit_event(
    event_type => 'sequence.created',
    category => 'data',
    target_type => 'sequence',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'created a sequence',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'status', v_row."status")
  );
  else
    perform "better_supabase".emit_event('sequence.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'status', v_row."status"), 'sequences/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/sequences');
  perform better_supabase.audit_event(
    event_type => 'sequence.updated',
    category => 'data',
    target_type => 'sequence',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'updated a sequence',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'status', v_row."status")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'status', v_row."status", 'exitOnReply', v_row."exit_on_reply", 'accountId', v_row."mail_account_id", 'steps', v_row."steps", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('counts', (select jsonb_build_object('active', count(*) filter (where m."status" = 'active'), 'paused', count(*) filter (where m."status" = 'paused'),
      'completed', count(*) filter (where m."status" = 'completed'), 'exited', count(*) filter (where m."status" = 'exited'),
      'replied', count(*) filter (where m."exit_reason" = 'replied'))
    from "better_supabase"."sequence_enrollments" m where m."sequence_id" = v_row."id"));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_variant (
  product         uuid,
  variant         uuid,
  sku             text,
  option_values   uuid[],
  title           text,
  barcode         text,
  weight_grams    integer,
  track_inventory boolean,
  allow_backorder boolean,
  clear           text[]  DEFAULT NULL::text[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_id uuid := save_variant.variant;
  v_created boolean := save_variant.variant is null;
  v_wanted uuid[];
  v_last text;
  v_rank text;
  v_sku text := save_variant.sku;
  v_defaults jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."products" x where x."id" = save_variant.product for update;
  if v_tenant is null then
    raise exception 'product not found' using errcode = 'P0002', hint = 'CATALOG_PRODUCT_NOT_FOUND';
  end if;
  if v_created then
    if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  else
    if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  end if;
  if exists (select 1 from unnest(coalesce(save_variant.clear, '{}'::text[])) c where c <> all ('{sku,title,barcode,weight}'::text[])) then
    raise exception 'clear names only sku, title, barcode, weight' using errcode = '22023', hint = 'CATALOG_CLEAR_INVALID';
  end if;
  if v_created or save_variant.option_values is not null then
  v_wanted := coalesce((select array_agg(distinct x order by x) from unnest(save_variant.option_values) x), '{}'::uuid[]);
  if cardinality(v_wanted) <> coalesce(cardinality(save_variant.option_values), 0)
    or exists (
      select 1 from unnest(v_wanted) x
      where not exists (
        select 1 from "better_supabase"."product_option_values" ov join "better_supabase"."product_options" o on o."id" = ov."option_id"
        where ov."id" = x and o."product_id" = save_variant.product
      )
    )
    or (select count(distinct ov."option_id") from "better_supabase"."product_option_values" ov where ov."id" = any (v_wanted)) <> cardinality(v_wanted)
    or (select count(*) from "better_supabase"."product_options" o where o."product_id" = save_variant.product) <> cardinality(v_wanted) then
    raise exception 'a variant needs exactly one value of each product option' using errcode = '22023', hint = 'CATALOG_VARIANT_OPTIONS';
  end if;
  if exists (
    select 1 from "better_supabase"."product_variants" x
    where x."product_id" = save_variant.product
      and x."id" is distinct from save_variant.variant
      and coalesce((select array_agg(y."option_value_id" order by y."option_value_id") from "better_supabase"."product_variant_values" y where y."variant_id" = x."id"), '{}'::uuid[]) = v_wanted
  ) then
    raise exception 'another variant has these option values' using errcode = '23505', hint = 'CATALOG_VARIANT_DUPLICATE';
  end if;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_variant_save"(uuid, uuid, text, uuid[])');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text, $4::uuid[])', v_hook::oid::regproc)
        using save_variant.product, save_variant.variant, save_variant.sku, v_wanted;
    end if;
  end;
  begin
    if v_created then
      select max(x."rank" collate "C") into v_last from "better_supabase"."product_variants" x where x."product_id" = save_variant.product;
      v_rank := case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end;
      execute coalesce((select 'select jsonb_build_object(' || string_agg(pg_catalog.quote_literal(a.attname) || ', ' || pg_catalog.pg_get_expr(d.adbin, d.adrelid), ', ') || ')'
    from pg_catalog.pg_attrdef d join pg_catalog.pg_attribute a on a.attrelid = d.adrelid and a.attnum = d.adnum
    where d.adrelid = '"better_supabase"."product_variants"'::regclass and a.attname = any (array[case when save_variant.sku is null then 'sku' end, case when save_variant.title is null then 'title' end, case when save_variant.barcode is null then 'barcode' end, case when save_variant.weight_grams is null then 'weight_grams' end]::text[])), 'select ''{}''::jsonb') into v_defaults;
      insert into "better_supabase"."product_variants" as x ("tenant_id", "product_id", "sku", "title", "barcode", "weight_grams", "track_inventory", "allow_backorder", "rank")
      values (v_tenant, save_variant.product, coalesce(save_variant.sku, (jsonb_populate_record(null::"better_supabase"."product_variants", v_defaults))."sku"), coalesce(save_variant.title, (jsonb_populate_record(null::"better_supabase"."product_variants", v_defaults))."title"), coalesce(save_variant.barcode, (jsonb_populate_record(null::"better_supabase"."product_variants", v_defaults))."barcode"), coalesce(save_variant.weight_grams, (jsonb_populate_record(null::"better_supabase"."product_variants", v_defaults))."weight_grams"), coalesce(save_variant.track_inventory, true), coalesce(save_variant.allow_backorder, false), v_rank)
      returning x."id", x."sku" into v_id, v_sku;
    else
      update "better_supabase"."product_variants" x set "sku" = case when 'sku' = any (coalesce(save_variant.clear, '{}'::text[])) then null else coalesce(save_variant.sku, x."sku") end, "title" = case when 'title' = any (coalesce(save_variant.clear, '{}'::text[])) then null else coalesce(save_variant.title, x."title") end, "barcode" = case when 'barcode' = any (coalesce(save_variant.clear, '{}'::text[])) then null else coalesce(save_variant.barcode, x."barcode") end, "weight_grams" = case when 'weight' = any (coalesce(save_variant.clear, '{}'::text[])) then null else coalesce(save_variant.weight_grams, x."weight_grams") end, "track_inventory" = coalesce(save_variant.track_inventory, x."track_inventory"), "allow_backorder" = coalesce(save_variant.allow_backorder, x."allow_backorder"), "updated_at" = now()
      where x."id" = save_variant.variant and x."product_id" = save_variant.product
      returning x."rank", x."sku" into v_rank, v_sku;
      if not found then
        raise exception 'variant not found' using errcode = 'P0002', hint = 'CATALOG_VARIANT_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    declare
      v_constraint text;
    begin
      get stacked diagnostics v_constraint = constraint_name;
      if exists (
        select 1 from pg_catalog.pg_index i
        join pg_catalog.pg_class c on c.oid = i.indexrelid
        where i.indrelid = '"better_supabase"."product_variants"'::regclass and c.relname = v_constraint
          and (exists (select 1 from pg_catalog.pg_attribute a where a.attrelid = i.indrelid and a.attnum = any (i.indkey) and a.attname = 'sku')
            or coalesce(pg_catalog.pg_get_expr(i.indexprs, i.indrelid), '') ~ ('\m' || 'sku' || '\M'))
      ) then
        raise exception 'another variant has this SKU' using errcode = '23505', hint = 'CATALOG_SKU_TAKEN';
      end if;
      raise;
    end;
  end;
  if v_wanted is not null then
  delete from "better_supabase"."product_variant_values" x where x."variant_id" = v_id and not (x."option_value_id" = any (v_wanted));
  insert into "better_supabase"."product_variant_values" ("tenant_id", "variant_id", "option_value_id")
  select v_tenant, v_id, x from unnest(v_wanted) x
  on conflict do nothing;
  end if;
  if v_created then
    perform "better_supabase".emit_event('product_variant.created', jsonb_build_object('organizationId', v_tenant, 'id', v_id, 'productId', save_variant.product, 'sku', v_sku), 'variants/' || v_id::text, (v_tenant)::text, null, 'better-supabase/catalog');
  else
    perform "better_supabase".emit_event('product_variant.updated', jsonb_build_object('organizationId', v_tenant, 'id', v_id, 'productId', save_variant.product, 'sku', v_sku), 'variants/' || v_id::text, (v_tenant)::text, null, 'better-supabase/catalog');
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_variant_save"(uuid, boolean)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::boolean)', v_hook::oid::regproc)
        using v_id, v_created;
    end if;
  end;
  return jsonb_build_object('id', v_id, 'sku', v_sku, 'rank', v_rank);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_view (
  tenant  uuid,
  list    text,
  name    text,
  kind    text,
  scope   text,
  team    text,
  state   jsonb,
  view_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_id uuid := save_view.view_id;
  v_inserted boolean := save_view.view_id is null;
  v_row "better_supabase"."shared_views";
  v_last text;
  v_rank text;
  v_service boolean := auth.role() = 'service_role';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if save_view.scope is null or save_view.scope not in ('user', 'team', 'tenant') then
    raise exception 'scope must be user, team or tenant' using errcode = '22023', hint = 'SAVED_VIEW_INVALID';
  end if;
  if save_view.kind is null or save_view.kind not in ('table', 'board', 'calendar', 'timeline', 'gantt') then
    raise exception 'unknown view kind' using errcode = '22023', hint = 'SAVED_VIEW_INVALID';
  end if;
  if save_view.state is null or jsonb_typeof(save_view.state) <> 'object' then
    raise exception 'state must be an object' using errcode = '22023', hint = 'SAVED_VIEW_INVALID';
  end if;
  if not (v_service or coalesce(better_supabase.can('tenant', save_view.tenant, 'saved_views.read'), false)) then
    raise exception 'not allowed to save views' using errcode = '42501', hint = 'SAVED_VIEW_FORBIDDEN';
  end if;
  if save_view.scope = 'user' and auth.uid() is null then
    raise exception 'a personal view needs a signed-in user' using errcode = '22023', hint = 'SAVED_VIEW_INVALID';
  end if;
  if save_view.scope <> 'user' and not (v_service or coalesce(better_supabase.can('tenant', save_view.tenant, 'saved_views.share'), false)) then
    raise exception 'not allowed to share views' using errcode = '42501', hint = 'SAVED_VIEW_FORBIDDEN';
  end if;
  if save_view.scope = 'team' then
    if save_view.team is null then
      raise exception 'a team view needs a team' using errcode = '22023', hint = 'SAVED_VIEW_INVALID';
    end if;
    if not (v_service or save_view.team in (select t::text from "better_supabase"."team_ids_of"((select auth.uid())) t)) then
      raise exception 'not a member of this team' using errcode = '42501', hint = 'SAVED_VIEW_FORBIDDEN';
    end if;
  end if;
  if v_id is not null then
    select * into v_row from "better_supabase"."shared_views" where "id" = v_id and "tenant_id" = save_view.tenant for update;
    if not found then
      raise exception 'saved view not found' using errcode = 'P0002', hint = 'SAVED_VIEW_NOT_FOUND';
    end if;
    if not (auth.role() = 'service_role'
    or (v_row."scope" = 'user' and coalesce(v_row."owner_id" = auth.uid(), false))
    or (v_row."scope" <> 'user' and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'saved_views.share'), false))) then
      raise exception 'not allowed to change this view' using errcode = '42501', hint = 'SAVED_VIEW_FORBIDDEN';
    end if;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_view_save"(uuid, text, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::jsonb)', v_hook::oid::regproc)
        using save_view.tenant, save_view.list, save_view.scope, save_view.state;
    end if;
  end;
  if v_id is null then
    select max(v."rank" collate "C") into v_last from "better_supabase"."shared_views" v
      where v."tenant_id" = save_view.tenant and v."list" = save_view.list;
    v_rank := case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end;
    insert into "better_supabase"."shared_views" ("tenant_id", "list", "scope", "owner_id", "team_id", "name", "kind", "state", "rank")
    values (save_view.tenant, save_view.list, save_view.scope, auth.uid(),
      case when save_view.scope = 'team' then save_view.team end,
      save_view.name, save_view.kind, save_view.state, v_rank)
    returning "id" into v_id;
  else
    update "better_supabase"."shared_views" set
      "list" = save_view.list,
      "scope" = save_view.scope,
      "team_id" = case when save_view.scope = 'team' then save_view.team end,
      "owner_id" = coalesce("owner_id", auth.uid()),
      "name" = save_view.name,
      "kind" = save_view.kind,
      "state" = save_view.state,
      -- The default is per list, scope and team; moving the view drops it.
      "is_default" = case
        when "scope" = save_view.scope and "list" = save_view.list
          and "team_id" is not distinct from case when save_view.scope = 'team' then save_view.team end
        then "is_default" else false end,
      "updated_at" = now()
    where "id" = v_id
    returning "rank" into v_rank;
  end if;
  if v_inserted then
    perform "better_supabase".emit_event('saved_view.created', jsonb_build_object('organizationId', save_view.tenant, 'id', v_id, 'kind', save_view.kind, 'name', save_view.name), 'saved-views/' || v_id::text, (save_view.tenant)::text, null, 'better-supabase/saved-views');
  else
    perform "better_supabase".emit_event('saved_view.updated', jsonb_build_object('organizationId', save_view.tenant, 'id', v_id, 'kind', save_view.kind, 'name', save_view.name), 'saved-views/' || v_id::text, (save_view.tenant)::text, null, 'better-supabase/saved-views');
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_view_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return jsonb_build_object('id', v_id, 'rank', v_rank);
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
  select * into v_row from "better_supabase"."work_items" x where x."id" = save_work_item_checklist_item.work_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false)) and x."archived_at" is null;
  if v_row."id" is null then
    raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
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
        raise exception 'no such checklist item on this work item' using errcode = 'P0002', hint = 'TASK_CHECKLIST_ITEM_NOT_FOUND';
      end if;
    end if;
  exception when check_violation or not_null_violation or invalid_text_representation then
    raise exception 'a checklist item needs a title of 1 to 500 characters and a valid rank' using errcode = '22023', hint = 'TASK_CHECKLIST_ITEM_INVALID';
  end;
  perform "better_supabase".emit_event('task.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'fields', jsonb_build_array('checklist')), 'work-items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  return (select jsonb_build_object('id', y."id", 'workItemId', y."work_item_id", 'title', y."title", 'done', y."done", 'doneAt', y."done_at", 'doneBy', y."done_by", 'rank', y."rank", 'createdAt', y."created_at") from "better_supabase"."work_item_checklist_items" y where y."id" = v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.scim_save_group (
  tenant  uuid,
  id      uuid,
  data    jsonb,
  version integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."scim_groups";
  v_name text := scim_save_group.data ->> 'displayName';
  v_members uuid[];
  v_before uuid[] := '{}';
  v_member uuid;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role serves SCIM' using errcode = '42501', hint = 'SSO_FORBIDDEN';
  end if;
  if v_name is null or length(trim(v_name)) = 0 then
    raise exception 'displayName is required' using errcode = '22023', hint = 'SCIM_INVALID';
  end if;
  begin
    select coalesce(array_agg(distinct (w.value)::uuid), '{}') into v_members
    from jsonb_array_elements_text(coalesce(scim_save_group.data -> 'members', '[]'::jsonb)) w;
  exception when invalid_text_representation then
    raise exception 'members must be SCIM user ids' using errcode = '22023', hint = 'SCIM_INVALID';
  end;
  if exists (
    select 1 from unnest(v_members) w(member)
    where not exists (select 1 from "better_supabase"."scim_users" x where x."organization_id" = scim_save_group.tenant and x."id" = w.member)
  ) then
    raise exception 'members must be SCIM users of the organization' using errcode = '22023', hint = 'SCIM_INVALID';
  end if;
  if scim_save_group.id is null then
    insert into "better_supabase"."scim_groups" ("organization_id", "display_name", "external_id", "role")
    values (scim_save_group.tenant, v_name, scim_save_group.data ->> 'externalId', "better_supabase"."scim_group_role"(v_name))
    returning * into v_row;
  else
    select * into v_row from "better_supabase"."scim_groups" x where x."organization_id" = scim_save_group.tenant and x."id" = scim_save_group.id for update;
    if v_row."id" is null then
      raise exception 'No SCIM group has this id' using errcode = 'P0002', hint = 'SCIM_NOT_FOUND';
    end if;
    if scim_save_group.version is not null and scim_save_group.version <> v_row."version" then
      raise exception 'The group changed since version %', scim_save_group.version using errcode = 'P0001', hint = 'SCIM_PRECONDITION';
    end if;
    select coalesce(array_agg(sm."scim_user_id"), '{}') into v_before from "better_supabase"."scim_group_members" sm where sm."group_id" = v_row."id";
    update "better_supabase"."scim_groups" x set
      "display_name" = v_name,
      "external_id" = scim_save_group.data ->> 'externalId',
      "role" = "better_supabase"."scim_group_role"(v_name),
      "version" = x."version" + 1,
      "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
    delete from "better_supabase"."scim_group_members" sm where sm."group_id" = v_row."id" and not (sm."scim_user_id" = any (v_members));
  end if;
  insert into "better_supabase"."scim_group_members" ("group_id", "scim_user_id")
  select v_row."id", w.member from unnest(v_members) w(member)
  on conflict do nothing;
  for v_member in select distinct w.member from unnest(v_before || v_members) w(member) loop
    perform "better_supabase"."scim_sync_member"(v_member);
  end loop;
  if scim_save_group.id is null then
    perform "better_supabase".emit_event('scim_group.created', jsonb_build_object('organizationId', scim_save_group.tenant::text, 'scimGroupId', v_row."id"), 'organizations/' || scim_save_group.tenant::text, (scim_save_group.tenant)::text, null, 'better-supabase/sso');
  perform better_supabase.audit_event(
    event_type => 'scim_group.created',
    category => 'security',
    target_type => 'scim_group',
    record_id => v_row."id"::text,
    tenant => (scim_save_group.tenant)::uuid,
    metadata => jsonb_build_object('organizationId', scim_save_group.tenant::text, 'scimGroupId', v_row."id")
  );
  else
    perform "better_supabase".emit_event('scim_group.updated', jsonb_build_object('organizationId', scim_save_group.tenant::text, 'scimGroupId', v_row."id"), 'organizations/' || scim_save_group.tenant::text, (scim_save_group.tenant)::text, null, 'better-supabase/sso');
  perform better_supabase.audit_event(
    event_type => 'scim_group.updated',
    category => 'security',
    target_type => 'scim_group',
    record_id => v_row."id"::text,
    tenant => (scim_save_group.tenant)::uuid,
    metadata => jsonb_build_object('organizationId', scim_save_group.tenant::text, 'scimGroupId', v_row."id")
  );
  end if;
  return (select to_jsonb(x.*) || jsonb_build_object('members', (
      select coalesce(jsonb_agg(jsonb_build_object('value', su."id", 'display', coalesce(su."display_name", su."user_name")) order by su."user_name"), '[]'::jsonb)
      from "better_supabase"."scim_group_members" sm join "better_supabase"."scim_users" su on su."id" = sm."scim_user_id"
      where sm."group_id" = x."id"
    )) from "better_supabase"."scim_groups" x where x."id" = v_row."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.scim_save_user (
  tenant  uuid,
  id      uuid,
  data    jsonb,
  version integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."scim_users";
  v_emails jsonb := coalesce(scim_save_user.data -> 'emails', '[]'::jsonb);
  v_name text := scim_save_user.data ->> 'userName';
  v_email text;
  v_user uuid;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role serves SCIM' using errcode = '42501', hint = 'SSO_FORBIDDEN';
  end if;
  if v_name is null or length(trim(v_name)) = 0 then
    raise exception 'userName is required' using errcode = '22023', hint = 'SCIM_INVALID';
  end if;
  if jsonb_typeof(v_emails) <> 'array' then
    raise exception 'emails must be an array' using errcode = '22023', hint = 'SCIM_INVALID';
  end if;
  v_email := lower(coalesce(
    (select e ->> 'value' from jsonb_array_elements(v_emails) e where (e ->> 'primary')::boolean limit 1),
    v_emails -> 0 ->> 'value',
    case when v_name like '%@%' then v_name end
  ));
  if scim_save_user.id is null then
    insert into "better_supabase"."scim_users" ("organization_id", "external_id", "user_name", "display_name", "given_name", "family_name", "email", "emails", "active")
    values (scim_save_user.tenant, scim_save_user.data ->> 'externalId', v_name, scim_save_user.data ->> 'displayName',
      scim_save_user.data ->> 'givenName', scim_save_user.data ->> 'familyName', v_email, v_emails,
      coalesce((scim_save_user.data ->> 'active')::boolean, true))
    returning * into v_row;
  else
    select * into v_row from "better_supabase"."scim_users" x where x."organization_id" = scim_save_user.tenant and x."id" = scim_save_user.id for update;
    if v_row."id" is null then
      raise exception 'No SCIM user has this id' using errcode = 'P0002', hint = 'SCIM_NOT_FOUND';
    end if;
    if scim_save_user.version is not null and scim_save_user.version <> v_row."version" then
      raise exception 'The user changed since version %', scim_save_user.version using errcode = 'P0001', hint = 'SCIM_PRECONDITION';
    end if;
    update "better_supabase"."scim_users" x set
      "external_id" = scim_save_user.data ->> 'externalId',
      "user_name" = v_name,
      "display_name" = scim_save_user.data ->> 'displayName',
      "given_name" = scim_save_user.data ->> 'givenName',
      "family_name" = scim_save_user.data ->> 'familyName',
      "email" = v_email,
      "emails" = v_emails,
      "active" = coalesce((scim_save_user.data ->> 'active')::boolean, true),
      "version" = x."version" + 1,
      "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  end if;
  if v_row."user_id" is null and v_email is not null and exists (select 1 from "better_supabase"."organization_domains" vd where vd."organization_id" = scim_save_user.tenant and vd."verified_at" is not null and vd."domain" = lower(split_part(v_email, '@', 2))) then
    select au.id into v_user from auth.users au
    where lower(au.email) = v_email and au.email_confirmed_at is not null
      and not exists (select 1 from "better_supabase"."scim_users" y where y."organization_id" = scim_save_user.tenant and y."user_id" = au.id)
    limit 1;
    if v_user is not null then
      update "better_supabase"."scim_users" x set "user_id" = v_user where x."id" = v_row."id" returning * into v_row;
    end if;
  end if;
  perform "better_supabase"."scim_sync_member"(v_row."id");
  if scim_save_user.id is null then
    perform "better_supabase".emit_event('scim_user.created', jsonb_build_object('organizationId', scim_save_user.tenant::text, 'scimUserId', v_row."id"), 'organizations/' || scim_save_user.tenant::text, (scim_save_user.tenant)::text, null, 'better-supabase/sso');
  perform better_supabase.audit_event(
    event_type => 'scim_user.created',
    category => 'security',
    target_type => 'scim_user',
    record_id => v_row."id"::text,
    tenant => (scim_save_user.tenant)::uuid,
    metadata => jsonb_build_object('organizationId', scim_save_user.tenant::text, 'scimUserId', v_row."id")
  );
  else
    perform "better_supabase".emit_event('scim_user.updated', jsonb_build_object('organizationId', scim_save_user.tenant::text, 'scimUserId', v_row."id"), 'organizations/' || scim_save_user.tenant::text, (scim_save_user.tenant)::text, null, 'better-supabase/sso');
  perform better_supabase.audit_event(
    event_type => 'scim_user.updated',
    category => 'security',
    target_type => 'scim_user',
    record_id => v_row."id"::text,
    tenant => (scim_save_user.tenant)::uuid,
    metadata => jsonb_build_object('organizationId', scim_save_user.tenant::text, 'scimUserId', v_row."id")
  );
  end if;
  return (select to_jsonb(x.*) || jsonb_build_object('groups', (
      select coalesce(jsonb_agg(jsonb_build_object('value', sg."id", 'display', sg."display_name") order by sg."display_name"), '[]'::jsonb)
      from "better_supabase"."scim_group_members" sm join "better_supabase"."scim_groups" sg on sg."id" = sm."group_id"
      where sm."scim_user_id" = x."id"
    )) from "better_supabase"."scim_users" x where x."id" = v_row."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_ai_tool_policy (
  tenant uuid,
  tool   text,
  policy text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', set_ai_tool_policy.tenant, 'ai_chat.manage'), false)) then
    raise exception 'You may not change tool policies here' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  if set_ai_tool_policy.policy is null then
    delete from "better_supabase"."ai_tool_policies" x where x."organization_id" = set_ai_tool_policy.tenant and x."tool" = set_ai_tool_policy.tool;
    perform "better_supabase".emit_event('ai_tool_policy.updated', jsonb_build_object('organizationId', set_ai_tool_policy.tenant::text, 'tool', set_ai_tool_policy.tool, 'policy', set_ai_tool_policy.policy), 'organizations/' || set_ai_tool_policy.tenant::text || '/ai-tool-policies/' || set_ai_tool_policy.tool, (set_ai_tool_policy.tenant)::text, null, 'better-supabase/ai-chat');
  perform better_supabase.audit_event(
    event_type => 'ai_tool_policy.updated',
    category => 'ai',
    target_type => 'ai_tool_policy',
    record_id => set_ai_tool_policy.tool,
    tenant => (set_ai_tool_policy.tenant)::uuid,
    metadata => jsonb_build_object('organizationId', set_ai_tool_policy.tenant::text, 'tool', set_ai_tool_policy.tool, 'policy', set_ai_tool_policy.policy)
  );
    return jsonb_build_object('tool', set_ai_tool_policy.tool, 'policy', null);
  end if;
  insert into "better_supabase"."ai_tool_policies" ("organization_id", "tool", "policy")
  values (set_ai_tool_policy.tenant, set_ai_tool_policy.tool, set_ai_tool_policy.policy)
  on conflict ("organization_id", "tool") do update set "policy" = excluded."policy", "updated_at" = now();
  perform "better_supabase".emit_event('ai_tool_policy.updated', jsonb_build_object('organizationId', set_ai_tool_policy.tenant::text, 'tool', set_ai_tool_policy.tool, 'policy', set_ai_tool_policy.policy), 'organizations/' || set_ai_tool_policy.tenant::text || '/ai-tool-policies/' || set_ai_tool_policy.tool, (set_ai_tool_policy.tenant)::text, null, 'better-supabase/ai-chat');
  perform better_supabase.audit_event(
    event_type => 'ai_tool_policy.updated',
    category => 'ai',
    target_type => 'ai_tool_policy',
    record_id => set_ai_tool_policy.tool,
    tenant => (set_ai_tool_policy.tenant)::uuid,
    metadata => jsonb_build_object('organizationId', set_ai_tool_policy.tenant::text, 'tool', set_ai_tool_policy.tool, 'policy', set_ai_tool_policy.policy)
  );
  return jsonb_build_object('tool', set_ai_tool_policy.tool, 'policy', set_ai_tool_policy.policy);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_contract_obligation_status (
  obligation_id uuid,
  status        text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."contract_obligations"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."contract_obligations" x where x."id" = set_contract_obligation_status.obligation_id for update;
  if not found then
    raise exception 'obligation not found' using errcode = 'P0002', hint = 'CONTRACT_OBLIGATION_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'contracts.write'), false)) or coalesce(v_row."owner_id" = auth.uid(), false)) then
    raise exception 'not allowed to change this obligation' using errcode = '42501', hint = 'CONTRACT_FORBIDDEN';
  end if;
  if set_contract_obligation_status.status is null or set_contract_obligation_status.status not in ('open', 'done', 'waived') then
    raise exception 'status must be open, done or waived' using errcode = '22023', hint = 'CONTRACT_INVALID';
  end if;
  update "better_supabase"."contract_obligations" x set "status" = set_contract_obligation_status.status,
    "completed_at" = case when set_contract_obligation_status.status = 'open' then null else now() end,
    "completed_by" = case when set_contract_obligation_status.status = 'open' then null else auth.uid() end,
    "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  perform "better_supabase".emit_event('contract_obligation.status_changed', jsonb_build_object('organizationId', v_row."tenant_id", 'obligationId', v_row."id", 'contractId', v_row."contract_id", 'status', v_row."status"), 'obligations/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/contracts');
  perform better_supabase.audit_event(
    event_type => 'contract_obligation.status_changed',
    category => 'data',
    target_type => 'obligation',
    record_id => v_row."id"::text,
    summary => 'marked obligation' || ' ' || v_row."title",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'obligationId', v_row."id", 'contractId', v_row."contract_id", 'status', v_row."status")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'contractId', v_row."contract_id", 'title', v_row."title", 'description', v_row."description", 'dueOn', v_row."due_on", 'ownerId', v_row."owner_id", 'status', v_row."status", 'overdue', (v_row."status" = 'open' and v_row."due_on" < current_date), 'completedAt', v_row."completed_at", 'completedBy', v_row."completed_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
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
    perform "better_supabase".emit_event('flag.override_changed', jsonb_build_object('key', set_flag_override.key, 'variant', set_flag_override.variant, 'organizationId', set_flag_override.tenant::text, 'userId', set_flag_override.member, 'context', set_flag_override.context, 'contextKey', set_flag_override.context_key), 'flags/' || set_flag_override.key, (set_flag_override.tenant)::text, null, 'better-supabase/flags');
  perform better_supabase.audit_event(
    event_type => 'flag.override_changed',
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
  perform "better_supabase".emit_event('flag.override_changed', jsonb_build_object('key', set_flag_override.key, 'variant', set_flag_override.variant, 'organizationId', set_flag_override.tenant::text, 'userId', set_flag_override.member, 'context', set_flag_override.context, 'contextKey', set_flag_override.context_key), 'flags/' || set_flag_override.key, (set_flag_override.tenant)::text, null, 'better-supabase/flags');
  perform better_supabase.audit_event(
    event_type => 'flag.override_changed',
    category => 'configuration',
    target_type => 'flag',
    record_id => set_flag_override.key,
    tenant => (set_flag_override.tenant)::uuid,
    metadata => jsonb_build_object('key', set_flag_override.key, 'variant', set_flag_override.variant, 'organizationId', set_flag_override.tenant::text, 'userId', set_flag_override.member, 'context', set_flag_override.context, 'contextKey', set_flag_override.context_key)
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_maintenance_request_assignees (
  work_item uuid,
  users     uuid[]
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."maintenance_requests";
  v_users uuid[] := array(select distinct x from unnest(coalesce(set_maintenance_request_assignees.users, '{}')) x where x is not null);
  v_added uuid[];
  v_new uuid[];
  v_claims text;
  v_user uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."maintenance_requests" x where x."id" = set_maintenance_request_assignees.work_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'maintenance.write'), false));
  if v_row."id" is null then
    raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  v_new := array(select x from unnest(v_users) x where x is distinct from auth.uid() and not exists (
    select 1 from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = v_row."id" and y."user_id" = x));
  v_added := array(select x from unnest(v_users) x where not exists (
    select 1 from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = v_row."id" and y."user_id" = x));
  delete from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = v_row."id" and not (y."user_id" = any (v_users));
  insert into "better_supabase"."maintenance_request_assignees" ("tenant_id", "maintenance_request_id", "user_id")
  select v_row."tenant_id", v_row."id", x from unnest(v_users) x
  on conflict do nothing;
  foreach v_user in array v_users loop
    insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
    values (v_row."tenant_id", v_user, 'maintenance_request', v_row."id"::text, 'participating')
    on conflict do nothing;
  end loop;
  if cardinality(v_new) > 0 then
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'maintenance_request.assigned',
      'tenant', v_row."tenant_id",
      'actor', auth.uid(),
      'subject_type', 'maintenance_request',
      'subject_id', v_row."id"::text,
      'subject_label', v_row."title",
      'summary', v_row."title",
      'action_path', null,
      'recipients', to_jsonb(v_new),
      'watchers', false,
      'key', 'task.assigned:' || v_row."id"::text || ':' || md5(array_to_string(v_new, ',')),
      'data', jsonb_build_object('maintenanceRequestId', v_row."id")
    ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  if cardinality(v_added) > 0 then
    perform "better_supabase".emit_event('maintenance_request.assigned', jsonb_build_object('organizationId', v_row."tenant_id", 'maintenanceRequestId', v_row."id", 'subjectType', 'maintenance_request', 'subjectId', v_row."id"::text, 'title', v_row."title", 'assigneeIds', to_jsonb(v_users), 'addedIds', to_jsonb(v_added)), 'maintenance-requests/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/maintenance');
  end if;
  return cardinality(v_users);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_product_options (
  product         uuid,
  options         jsonb,
  title_separator text  DEFAULT ' / '::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_slug text;
  v_item jsonb;
  v_option uuid;
  v_ids uuid[] := '{}';
  v_variant uuid;
  v_combo uuid[];
  v_label text;
  v_count numeric := 1;
  v_sku_required boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."slug" into v_tenant, v_slug from "better_supabase"."products" x where x."id" = set_product_options.product for update;
  if v_tenant is null then
    raise exception 'product not found' using errcode = 'P0002', hint = 'CATALOG_PRODUCT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  if jsonb_typeof(set_product_options.options) is distinct from 'array'
    or exists (
      select 1 from jsonb_array_elements(set_product_options.options) e
      where jsonb_typeof(e) is distinct from 'object'
        or jsonb_typeof(e -> 'name') is distinct from 'string'
        or jsonb_typeof(e -> 'values') is distinct from 'array'
        or exists (select 1 from jsonb_array_elements(e -> 'values') y where jsonb_typeof(y) <> 'string')
    ) then
    raise exception 'options is a list of { name, values } with text values' using errcode = '22023', hint = 'CATALOG_OPTIONS_INVALID';
  end if;
  if (select count(distinct e ->> 'name') from jsonb_array_elements(set_product_options.options) e) <> jsonb_array_length(set_product_options.options) then
    raise exception 'the list names an option twice' using errcode = '23505', hint = 'CATALOG_OPTION_TAKEN';
  end if;
  for v_item in select e from jsonb_array_elements(set_product_options.options) e loop
    v_count := v_count * jsonb_array_length(v_item -> 'values');
  end loop;
  if v_count > 100 then
    raise exception 'a product has at most 100 variants' using errcode = '22023', hint = 'CATALOG_VARIANT_LIMIT';
  end if;
  for v_option in
    select x."id" from "better_supabase"."product_options" x
    where x."product_id" = set_product_options.product
      and not (x."name" = any (array(select e ->> 'name' from jsonb_array_elements(set_product_options.options) e)))
  loop
    delete from "better_supabase"."product_variant_values" y using "better_supabase"."product_option_values" z where y."option_value_id" = z."id" and z."option_id" = v_option;
    delete from "better_supabase"."product_options" x where x."id" = v_option;
  end loop;
  for v_variant in
    select d.id from (
      select x."id" as id, row_number() over (partition by coalesce((select array_agg(y."option_value_id" order by y."option_value_id") from "better_supabase"."product_variant_values" y where y."variant_id" = x."id"), '{}'::uuid[]) order by x."rank" collate "C", x."id") as n
      from "better_supabase"."product_variants" x where x."product_id" = set_product_options.product
    ) d where d.n > 1
  loop
    if exists (select 1 from "better_supabase"."ledger_accounts" sa where sa."managed_by" = 'inventory' and sa."kind" = 'stock' and (case when sa."kind" = 'stock' then (sa."metadata" ->> 'variantId')::uuid end) = v_variant) then
      raise exception 'a variant this list removes is still in use' using errcode = '23503', hint = 'CATALOG_OPTION_VALUE_IN_USE';
      continue;
    end if;
    begin
      delete from "better_supabase"."product_variants" x where x."id" = v_variant;
      perform "better_supabase".emit_event('product_variant.deleted', jsonb_build_object('organizationId', v_tenant, 'id', v_variant, 'productId', set_product_options.product), 'variants/' || v_variant::text, (v_tenant)::text, null, 'better-supabase/catalog');
    exception when foreign_key_violation then
      raise exception 'a variant this list removes is still in use' using errcode = '23503', hint = 'CATALOG_OPTION_VALUE_IN_USE';
    end;
  end loop;
  for v_item in select e from jsonb_array_elements(set_product_options.options) with ordinality as a(e, n) order by a.n loop
    select x."id" into v_option from "better_supabase"."product_options" x where x."product_id" = set_product_options.product and x."name" = v_item ->> 'name';
    v_option := ("better_supabase"."save_product_option"(set_product_options.product, v_option, v_item ->> 'name', array(select y from jsonb_array_elements_text(v_item -> 'values') with ordinality as b(y, n) order by b.n)) ->> 'id')::uuid;
    v_ids := v_ids || v_option;
  end loop;
  if cardinality(v_ids) > 0 then
    perform "better_supabase"."reorder_product_options"(set_product_options.product, v_ids);
  end if;
  select a.attnotnull into v_sku_required from pg_catalog.pg_attribute a
  where a.attrelid = '"better_supabase"."product_variants"'::regclass and a.attname = 'sku';
  for v_combo, v_label in
    with recursive k as (
      select x."id" as id, row_number() over (order by x."rank" collate "C") as n
      from "better_supabase"."product_options" x where x."product_id" = set_product_options.product
    ), z as (
      select y."id" as id, y."value" as value, y."option_id" as option, row_number() over (partition by y."option_id" order by y."rank" collate "C") as n
      from "better_supabase"."product_option_values" y where y."option_id" in (select k.id from k)
    ), c(depth, ids, labels, sort) as (
      select 0::bigint, '{}'::uuid[], '{}'::text[], '{}'::bigint[]
      union all
      select k.n, c.ids || z.id, c.labels || z.value, c.sort || z.n
      from c join k on k.n = c.depth + 1 join z on z.option = k.id
    )
    select c.ids, array_to_string(c.labels, '-') from c where c.depth = (select count(*) from k) order by c.sort
  loop
    if not exists (
      select 1 from "better_supabase"."product_variants" x
      where x."product_id" = set_product_options.product
        and coalesce((select array_agg(y."option_value_id" order by y."option_value_id") from "better_supabase"."product_variant_values" y where y."variant_id" = x."id"), '{}'::uuid[]) = (select coalesce(array_agg(u order by u), '{}'::uuid[]) from unnest(v_combo) u)
    ) then
      perform "better_supabase"."save_variant"(set_product_options.product, null, case when v_sku_required then upper(trim(both '-' from regexp_replace(concat_ws('-', v_slug, nullif(v_label, '')), '[^A-Za-z0-9]+', '-', 'g'))) end, v_combo, null, null, null, null, null);
    end if;
  end loop;
  if set_product_options.title_separator is not null then
    update "better_supabase"."product_variants" x set "title" = t.title, "updated_at" = now()
    from (
      select y."variant_id" as variant, string_agg(z."value", set_product_options.title_separator order by k."rank" collate "C") as title
      from "better_supabase"."product_variant_values" y
      join "better_supabase"."product_option_values" z on z."id" = y."option_value_id"
      join "better_supabase"."product_options" k on k."id" = z."option_id"
      where k."product_id" = set_product_options.product
      group by y."variant_id"
    ) t
    where x."id" = t.variant and x."title" is distinct from t.title;
  end if;
  return jsonb_build_object(
    'options', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', k."id",
        'name', k."name",
        'values', (select coalesce(jsonb_agg(jsonb_build_object('id', z."id", 'value', z."value") order by z."rank" collate "C"), '[]'::jsonb) from "better_supabase"."product_option_values" z where z."option_id" = k."id")
      ) order by k."rank" collate "C"), '[]'::jsonb)
      from "better_supabase"."product_options" k where k."product_id" = set_product_options.product
    ),
    'variants', (
      select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'sku', x."sku", 'optionValueIds', to_jsonb(coalesce((select array_agg(y."option_value_id" order by y."option_value_id") from "better_supabase"."product_variant_values" y where y."variant_id" = x."id"), '{}'::uuid[]))) order by x."rank" collate "C"), '[]'::jsonb)
      from "better_supabase"."product_variants" x where x."product_id" = set_product_options.product
    )
  );
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
  if v_row."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'automations.read'), false)) then
    raise exception 'No rule you can read has this id' using errcode = 'P0002', hint = 'AUTOMATION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'automations.publish'), false)) then
    raise exception 'Publishing rules needs the publish permission' using errcode = '42501', hint = 'AUTOMATION_FORBIDDEN';
  end if;
  if v_row."enabled" = coalesce(set_rule_enabled.enabled, false) then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."organization_id", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'name', v_row."name", 'description', v_row."description", 'conditions', v_row."conditions", 'actions', v_row."actions", 'enabled', v_row."enabled", 'stopProcessing', v_row."stop_processing", 'rank', v_row."rank", 'version', v_row."version", 'createdBy', v_row."created_by", 'updatedBy', v_row."updated_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'defaultKey', v_row."default_key");
  end if;
  update "better_supabase"."rules" x set "enabled" = coalesce(set_rule_enabled.enabled, false), "updated_by" = auth.uid(), "updated_at" = now()
  where x."id" = v_row."id" returning * into v_row;
  if v_row."enabled" then
    perform "better_supabase".emit_event('automation.enabled', jsonb_build_object('organizationId', v_row."organization_id"::text, 'ruleId', v_row."id"::text, 'name', v_row."name", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'version', v_row."version"), 'rules/' || v_row."id"::text, (v_row."organization_id")::text, null, 'better-supabase/automations');
  perform better_supabase.audit_event(
    event_type => 'automation.enabled',
    category => 'configuration',
    target_type => 'rule',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'ruleId', v_row."id"::text, 'name', v_row."name", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'version', v_row."version"),
    actor_id => auth.uid()
  );
  else
    perform "better_supabase".emit_event('automation.disabled', jsonb_build_object('organizationId', v_row."organization_id"::text, 'ruleId', v_row."id"::text, 'name', v_row."name", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'version', v_row."version"), 'rules/' || v_row."id"::text, (v_row."organization_id")::text, null, 'better-supabase/automations');
  perform better_supabase.audit_event(
    event_type => 'automation.disabled',
    category => 'configuration',
    target_type => 'rule',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'ruleId', v_row."id"::text, 'name', v_row."name", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'version', v_row."version"),
    actor_id => auth.uid()
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."organization_id", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'name', v_row."name", 'description', v_row."description", 'conditions', v_row."conditions", 'actions', v_row."actions", 'enabled', v_row."enabled", 'stopProcessing', v_row."stop_processing", 'rank', v_row."rank", 'version', v_row."version", 'createdBy', v_row."created_by", 'updatedBy', v_row."updated_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'defaultKey', v_row."default_key");
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
  v_added uuid[];
  v_new uuid[];
  v_claims text;
  v_user uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."work_items" x where x."id" = set_work_item_assignees.work_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false));
  if v_row."id" is null then
    raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  v_new := array(select x from unnest(v_users) x where x is distinct from auth.uid() and not exists (
    select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = v_row."id" and y."user_id" = x));
  v_added := array(select x from unnest(v_users) x where not exists (
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
      'subject_label', v_row."title",
      'summary', v_row."title",
      'action_path', null,
      'recipients', to_jsonb(v_new),
      'watchers', false,
      'key', 'task.assigned:' || v_row."id"::text || ':' || md5(array_to_string(v_new, ',')),
      'data', jsonb_build_object('workItemId', v_row."id")
    ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  if cardinality(v_added) > 0 then
    perform "better_supabase".emit_event('task.assigned', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'assigneeIds', to_jsonb(v_users), 'addedIds', to_jsonb(v_added)), 'work-items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  end if;
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
  select * into v_row from "better_supabase"."work_items" x where x."id" = set_work_item_recurrence.work_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false)) and x."archived_at" is null;
  if v_row."id" is null then
    raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  if set_work_item_recurrence.rrule is null then
    delete from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = v_row."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = v_row."id"::text;
  else
    if set_work_item_recurrence.rrule !~ '^(RRULE:)?FREQ=(DAILY|WEEKLY|MONTHLY|YEARLY)(;[A-Z]+=[-+,0-9A-Z]+)*$' then
      raise exception 'rrule must be an RRULE such as FREQ=WEEKLY;BYDAY=MO' using errcode = '22023', hint = 'TASK_RECURRENCE_INVALID';
    end if;
    if not exists (select 1 from pg_catalog.pg_timezone_names z where z.name = coalesce(set_work_item_recurrence.tzid, 'UTC')) then
      raise exception 'tzid must be an IANA time zone' using errcode = '22023', hint = 'TASK_RECURRENCE_INVALID';
    end if;
    insert into "better_supabase"."recurrence_rules" ("tenant_id", "subject_type", "subject_id", "dtstart", "tzid", "rrule")
    values (v_row."tenant_id", 'work_item', v_row."id"::text, coalesce(v_row."due_at", now()), coalesce(set_work_item_recurrence.tzid, 'UTC'), regexp_replace(set_work_item_recurrence.rrule, '^RRULE:', ''))
    on conflict ("tenant_id", "subject_type", "subject_id")
    do update set "dtstart" = excluded."dtstart", "tzid" = excluded."tzid", "rrule" = excluded."rrule";
  end if;
  perform "better_supabase".emit_event('task.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'fields', jsonb_build_array('recurrence')), 'work-items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) -> 'recurrence' from "better_supabase"."work_items" x where x."id" = v_row."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.sign_signature (
  request_id          uuid,
  method              text,
  typed_name          text DEFAULT NULL::text,
  image_attachment_id uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_at timestamptz := clock_timestamp();
  v_req "better_supabase"."signature_requests"%rowtype;
  v_row "better_supabase"."signatures"%rowtype;
  v_typed text := nullif(trim(sign_signature.typed_name), '');
  v_current text;
  v_headers jsonb := nullif(current_setting('request.headers', true), '')::jsonb;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null then
    raise exception 'sign in to sign' using errcode = '42501', hint = 'SIGNATURE_FORBIDDEN';
  end if;
  if sign_signature.method not in ('drawn', 'typed', 'click') then
    raise exception 'method must be drawn, typed or click' using errcode = '22023', hint = 'SIGNATURE_METHOD_INVALID';
  end if;
  if sign_signature.method = 'typed' and v_typed is null then
    raise exception 'a typed signature needs the typed name' using errcode = '22023', hint = 'SIGNATURE_METHOD_INVALID';
  end if;
  if sign_signature.method = 'drawn' and sign_signature.image_attachment_id is null then
    raise exception 'a drawn signature needs its image attachment' using errcode = '22023', hint = 'SIGNATURE_METHOD_INVALID';
  end if;
  select * into v_req from "better_supabase"."signature_requests" x where x."id" = sign_signature.request_id for update;
  if not found then
    raise exception 'signature request not found' using errcode = 'P0002', hint = 'SIGNATURE_REQUEST_NOT_FOUND';
  end if;
  if not (v_me = any (v_req."signers")) then
    raise exception 'not a signer on this request' using errcode = '42501', hint = 'SIGNATURE_FORBIDDEN';
  end if;
  if v_req."status" <> 'pending' then
    raise exception 'this request is no longer pending' using errcode = '22023', hint = 'SIGNATURE_REQUEST_CLOSED';
  end if;
  if exists (select 1 from "better_supabase"."signatures" g where g."request_id" = v_req."id" and g."signer" = v_me) then
    raise exception 'you already signed this request' using errcode = '23505', hint = 'SIGNATURE_ALREADY_SIGNED';
  end if;
  select count(*) into v_count from "better_supabase"."signatures" g where g."request_id" = v_req."id";
  if v_req."sign_order" = 'sequential' and array_position(v_req."signers", v_me) <> v_count + 1 then
    raise exception 'an earlier signer hasn''t signed yet' using errcode = '55000', hint = 'SIGNATURE_OUT_OF_ORDER';
  end if;
  if sign_signature.image_attachment_id is not null and not exists (
    select 1 from "better_supabase"."attachments" a
    where a."id" = sign_signature.image_attachment_id
      and a."organization_id" = v_req."tenant_id"
  ) then
    raise exception 'the signature image isn''t an attachment in this organization' using errcode = '22023', hint = 'SIGNATURE_IMAGE_NOT_FOUND';
  end if;
  select encode(extensions.digest(coalesce(x."content"::text, '') || coalesce(x."storage_path", ''), 'sha256'), 'hex') into v_current
    from "better_supabase"."versions" x where x."id" = v_req."version_id";
  if v_current is distinct from v_req."content_hash" then
    raise exception 'the version to sign changed after the request was made' using errcode = '55000', hint = 'SIGNATURE_CONTENT_CHANGED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_signature_sign"(uuid, uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text)', v_hook::oid::regproc)
        using v_req."id", v_me, sign_signature.method;
    end if;
  end;
  insert into "better_supabase"."signatures" ("request_id", "tenant_id", "signer", "method", "typed_name", "image_attachment_id", "signed_hash", "ip", "user_agent", "signed_at")
  values (v_req."id", v_req."tenant_id", v_me, sign_signature.method, v_typed, sign_signature.image_attachment_id,
    encode(extensions.digest(v_req."id"::text || ':' || v_req."content_hash" || ':' || v_me::text || ':' || sign_signature.method || ':' || coalesce(v_typed, '') || ':' || coalesce(sign_signature.image_attachment_id::text, '') || ':' || to_char(v_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'), 'sha256'), 'hex'),
    left(nullif(trim(reverse(split_part(reverse(v_headers ->> 'x-forwarded-for'), ',', 1))), ''), 64),
    left(v_headers ->> 'user-agent', 512),
    v_at)
  returning * into v_row;
  perform "better_supabase".emit_event('signature_request.signed', jsonb_build_object('organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'signatureId', v_row."id", 'signer', v_me, 'method', v_row."method"), 'signature-requests/' || v_req."id"::text, (v_req."tenant_id")::text, null, 'better-supabase/signatures');
  perform better_supabase.audit_event(
    event_type => 'signature_request.signed',
    category => 'data',
    target_type => 'signature_request',
    record_id => v_req."id"::text,
    summary => 'signed ' || v_req."subject_type" || ' ' || v_req."subject_id",
    tenant => (v_req."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'signatureId', v_row."id", 'signer', v_me, 'method', v_row."method")
  );
  -- A signer who approves the linked request's current step decides it.
  if v_req."approval_request_id" is not null and "better_supabase"."approval_eligible"(v_req."approval_request_id") then
    perform "better_supabase"."decide_approval"(v_req."approval_request_id", 'approved', 'Signed electronically');
  end if;
  if v_count + 1 >= cardinality(v_req."signers") then
    update "better_supabase"."signature_requests" x set "status" = 'completed', "completed_at" = v_at
      where x."id" = v_req."id"
      returning * into v_req;
    perform "better_supabase".emit_event('signature_request.completed', jsonb_build_object('organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'versionId', v_req."version_id", 'meaning', v_req."meaning"), 'signature-requests/' || v_req."id"::text, (v_req."tenant_id")::text, null, 'better-supabase/signatures');
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_signature_sign"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_row."id", v_req."status";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'requestId', v_row."request_id", 'signer', v_row."signer", 'method', v_row."method", 'typedName', v_row."typed_name", 'imageAttachmentId', v_row."image_attachment_id", 'signedHash', v_row."signed_hash", 'ip', v_row."ip", 'userAgent', v_row."user_agent", 'signedAt', v_row."signed_at") || jsonb_build_object('requestStatus', v_req."status");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.take_forecast_snapshot (
  tenant   uuid,
  pipeline uuid,
  since    date,
  until    date,
  currency text,
  target   bigint DEFAULT NULL::bigint
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."forecast_snapshots";
  v_currency text := upper(take_forecast_snapshot.currency);
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', take_forecast_snapshot.tenant, 'forecasts.snapshot'), false)) then
    raise exception 'Taking a forecast snapshot needs the forecasts.snapshot permission' using errcode = '42501', hint = 'FORECAST_FORBIDDEN';
  end if;
  if take_forecast_snapshot.since is null or take_forecast_snapshot.until is null
    or take_forecast_snapshot.until < take_forecast_snapshot.since
    or take_forecast_snapshot.until - take_forecast_snapshot.since > 366 then
    raise exception 'until must be on or after since, at most a year later' using errcode = '22023', hint = 'FORECAST_INVALID';
  end if;
  if v_currency is null or v_currency !~ '^[A-Z]{3}$' then
    raise exception 'currency must be a three-letter code' using errcode = '22023', hint = 'FORECAST_INVALID';
  end if;
  if take_forecast_snapshot.target < 0 then
    raise exception 'target must not be negative' using errcode = '22023', hint = 'FORECAST_INVALID';
  end if;
  if take_forecast_snapshot.pipeline is not null and not exists (
    select 1 from "better_supabase"."pipelines" x
    where x."id" = take_forecast_snapshot.pipeline and x."tenant_id" = take_forecast_snapshot.tenant
  ) then
    raise exception 'The organization has no pipeline with this id' using errcode = 'P0002', hint = 'FORECAST_PIPELINE_UNKNOWN';
  end if;
  insert into "better_supabase"."forecast_snapshots" ("tenant_id", "pipeline_id", "period_start", "period_end", "currency", "target", "totals", "taken_by")
  values (take_forecast_snapshot.tenant, take_forecast_snapshot.pipeline, take_forecast_snapshot.since, take_forecast_snapshot.until, v_currency, take_forecast_snapshot.target, "better_supabase"."deal_forecast"(take_forecast_snapshot.tenant, take_forecast_snapshot.pipeline, take_forecast_snapshot.since, take_forecast_snapshot.until, v_currency, take_forecast_snapshot.target, null), auth.uid())
  returning * into v_row;
  insert into "better_supabase"."forecast_snapshot_deals" ("snapshot_id", "tenant_id", "deal_id", "name", "owner_user_id", "stage_id", "forecast_category", "outcome", "amount", "expected_close_on", "closed_at")
  select v_row."id", x."tenant_id", x."id", x."name", x."owner_user_id", x."stage_id", x."forecast_category"::text, x."outcome"::text, x."amount", x."expected_close_on", x."closed_at"
  from "better_supabase"."deals" x
  where x."tenant_id" = take_forecast_snapshot.tenant
    and x."currency" = v_currency
    and x."archived_at" is null
    and (take_forecast_snapshot.pipeline is null or x."pipeline_id" = take_forecast_snapshot.pipeline)
    and (
      (x."outcome" = 'open' and x."expected_close_on" between take_forecast_snapshot.since and take_forecast_snapshot.until)
      or (x."outcome" <> 'open' and x."closed_at"::date between take_forecast_snapshot.since and take_forecast_snapshot.until)
    );
  get diagnostics v_count = row_count;
  update "better_supabase"."forecast_snapshots" x set "deal_count" = v_count
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('forecast_snapshot.created', jsonb_build_object('organizationId', v_row."tenant_id", 'snapshotId', v_row."id", 'pipelineId', v_row."pipeline_id", 'since', v_row."period_start", 'until', v_row."period_end", 'currency', v_row."currency", 'dealCount', v_row."deal_count"), 'forecast-snapshots/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/forecasts');
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'pipelineId', v_row."pipeline_id", 'since', v_row."period_start", 'until', v_row."period_end", 'currency', v_row."currency", 'target', v_row."target"::text, 'totals', v_row."totals", 'dealCount', v_row."deal_count", 'takenBy', v_row."taken_by", 'takenAt', v_row."taken_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_activity (
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
  v_id uuid := update_activity.engagement;
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
  from "better_supabase"."engagements" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false));
  if v_tenant is null then
    raise exception 'no such engagement you can edit' using errcode = 'P0002', hint = 'ACTIVITY_NOT_FOUND';
  end if;
  if update_activity.attrs ? 'type' and not (update_activity.attrs ->> 'type' = any ('{call,email,meeting,note,task}'::text[])) then
    raise exception 'unknown engagement type' using errcode = '22023', hint = 'ACTIVITY_TYPE_INVALID';
  end if;
  if nullif(update_activity.attrs ->> 'audience', '') is not null and not (update_activity.attrs ->> 'audience' = any ('{team,subject,restricted}'::text[])) then
    raise exception 'audience must be one of team, subject, restricted' using errcode = '22023', hint = 'ACTIVITY_AUDIENCE_INVALID';
  end if;
  if update_activity.attrs ? 'restrictedRoles' and jsonb_typeof(update_activity.attrs -> 'restrictedRoles') not in ('array', 'null') then
    raise exception 'restrictedRoles must be a list of record team roles' using errcode = '22023', hint = 'ACTIVITY_AUDIENCE_INVALID';
  end if;
  if nullif(update_activity.attrs ->> 'category', '') is not null and not (update_activity.attrs ->> 'category' = any ('{general,care,medical,behavior,family,incident}'::text[])) then
    raise exception 'category must be one of general, care, medical, behavior, family, incident' using errcode = '22023', hint = 'ACTIVITY_CATEGORY_INVALID';
  end if;
  if exists (select 1 from "better_supabase"."engagements" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the engagement is locked: add an addendum with amend_activity instead' using errcode = '55000', hint = 'ACTIVITY_LOCKED';
  end if;
  update "better_supabase"."engagements" x set
    "type" = coalesce(update_activity.attrs ->> 'type', x."type"),
    "title" = coalesce(nullif(trim(update_activity.attrs ->> 'title'), ''), x."title"),
    "body" = case when update_activity.attrs ? 'body' then update_activity.attrs ->> 'body' else x."body" end,
    "outcome" = case when update_activity.attrs ? 'outcome' then update_activity.attrs ->> 'outcome' else x."outcome" end,
    "external_ref" = case when update_activity.attrs ? 'externalRef' then update_activity.attrs ->> 'externalRef' else x."external_ref" end,
    "owner_user_id" = case when update_activity.attrs ? 'ownerId' then nullif(update_activity.attrs ->> 'ownerId', '')::uuid else x."owner_user_id" end,
    "due_at" = case when update_activity.attrs ? 'dueAt' then (update_activity.attrs ->> 'dueAt')::timestamptz else x."due_at" end,
    "done_at" = case when update_activity.attrs ? 'doneAt' then (update_activity.attrs ->> 'doneAt')::timestamptz else x."done_at" end,
    "duration_seconds" = case when update_activity.attrs ? 'durationSeconds' then (update_activity.attrs ->> 'durationSeconds')::integer else x."duration_seconds" end,
    "audience" = case when update_activity.attrs ? 'audience' then coalesce(nullif(update_activity.attrs ->> 'audience', ''), 'team') else x."audience" end,
    "restricted_roles" = case when update_activity.attrs ? 'restrictedRoles' then nullif((select coalesce(array_agg(r.value order by r.ordinality), '{}'::text[]) from jsonb_array_elements_text(case when jsonb_typeof(update_activity.attrs -> 'restrictedRoles') = 'array' then update_activity.attrs -> 'restrictedRoles' else '[]'::jsonb end) with ordinality r), '{}') else x."restricted_roles" end,
    "category" = case when update_activity.attrs ? 'category' then nullif(update_activity.attrs ->> 'category', '') else x."category" end,
    "goal_id" = case when update_activity.attrs ? 'goalId' then nullif(update_activity.attrs ->> 'goalId', '')::uuid else x."goal_id" end,
    "locked_at" = case when update_activity.attrs ? 'type' then coalesce(x."locked_at", case when update_activity.attrs ->> 'type' = any ('{note,report}'::text[]) then x."created_at" + interval '24 hours' end) else x."locked_at" end,
    "updated_at" = now()
  where x."id" = v_id
  returning x."type", x."title", x."owner_user_id" into v_type, v_title, v_owner;
  if update_activity.subjects is not null then
    
  if jsonb_typeof(coalesce(update_activity.subjects, '[]')) <> 'array' then
    raise exception 'subjects must be a list of { type, id }' using errcode = '22023', hint = 'ACTIVITY_SUBJECTS_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(update_activity.subjects, '[]')) loop
    if not (case (v_item ->> 'type')
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'activity' then exists (select 1 from "better_supabase"."engagements" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'compliance_policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      else false
    end and "better_supabase"."can_subject"((v_item ->> 'type'), (v_item ->> 'id'), 'read')) then
      raise exception 'a subject is unknown or not readable in this organization' using errcode = '42501', hint = 'ACTIVITY_SUBJECT_FORBIDDEN';
    end if;
  end loop;
  delete from "better_supabase"."engagement_subjects" x where x."engagement_id" = v_id;
  insert into "better_supabase"."engagement_subjects" ("tenant_id", "engagement_id", "subject_type", "subject_id", "position")
  select v_tenant, v_id, s.value ->> 'type', s.value ->> 'id', s.ordinality::integer
  from jsonb_array_elements(coalesce(update_activity.subjects, '[]')) with ordinality s
  on conflict do nothing;
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  else
    v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = v_id), '[]'::jsonb);
    v_first := v_subjects -> 0;
  end if;
  perform "better_supabase".emit_event('activity.updated', jsonb_build_object('organizationId', v_tenant, 'engagementId', v_id, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects), 'engagements/' || v_id::text, (v_tenant::text)::text, null, 'better-supabase/activities');
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

CREATE OR REPLACE FUNCTION better_supabase.update_organization_domain (
  id             uuid,
  auto_join_role text    DEFAULT NULL::text,
  enforce_sso    boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."organization_domains";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."organization_domains" x where x."id" = update_organization_domain.id for update;
  if v_row."id" is null or not coalesce(better_supabase.can('tenant', v_row."organization_id", 'sso.manage'), false) then
    raise exception 'No domain you manage has this id' using errcode = 'P0002', hint = 'SSO_DOMAIN_NOT_FOUND';
  end if;
  if update_organization_domain.auto_join_role is not null and not (update_organization_domain.auto_join_role = any (array['admin', 'member', 'viewer']::text[])) then
    raise exception 'Auto-join cannot assign role %', update_organization_domain.auto_join_role using errcode = '22023', hint = 'SSO_ROLE_INVALID';
  end if;
  if update_organization_domain.auto_join_role is not null
    and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))
    and not coalesce(better_supabase.can_assign(v_row."organization_id", update_organization_domain.auto_join_role), false) then
    raise exception 'You may not assign role %', update_organization_domain.auto_join_role using errcode = '42501', hint = 'SSO_ROLE_FORBIDDEN';
  end if;
  if (update_organization_domain.enforce_sso or update_organization_domain.auto_join_role is not null) and v_row."verified_at" is null then
    raise exception 'Verify the domain first' using errcode = '22023', hint = 'SSO_DOMAIN_NOT_VERIFIED';
  end if;
  update "better_supabase"."organization_domains" x set "auto_join_role" = update_organization_domain.auto_join_role, "enforce_sso" = update_organization_domain.enforce_sso
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('sso_domain.updated', jsonb_build_object('organizationId', v_row."organization_id"::text, 'domainId', v_row."id", 'domain', v_row."domain", 'userId', auth.uid()), 'organizations/' || v_row."organization_id"::text, (v_row."organization_id")::text, null, 'better-supabase/sso');
  perform better_supabase.audit_event(
    event_type => 'sso_domain.updated',
    category => 'security',
    target_type => 'domain',
    record_id => v_row."id"::text,
    target_label => v_row."domain",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'domainId', v_row."id", 'domain', v_row."domain", 'userId', auth.uid()),
    actor_id => auth.uid()
  );
  return to_jsonb(v_row) - 'verification_token' || jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."domain", 'value', 'better-supabase-domain-verification=' || v_row."verification_token"));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_work_items (
  changes jsonb,
  atomic  boolean DEFAULT false
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
    raise exception 'changes must be a list of { workItemId, field, value }' using errcode = '22023', hint = 'TASK_CHANGES_INVALID';
  end if;
  for v_change in select value from jsonb_array_elements(update_work_items.changes) loop
    v_field := v_change ->> 'field';
    begin
      v_item := (v_change ->> 'workItemId')::uuid;
      if not exists (select 1 from "better_supabase"."work_items" x where x."id" = v_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false)) and x."archived_at" is null) then
        raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
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
      when 'window' then
        if jsonb_typeof(v_change -> 'value') <> 'object' then
          raise exception 'window must be an object of startAt and endAt' using errcode = '22023', hint = 'TASK_ATTRS_INVALID';
        end if;
        update "better_supabase"."work_items" x set
          "start_at" = case when v_change -> 'value' ? 'startAt' then (v_change -> 'value' ->> 'startAt')::timestamptz else x."start_at" end,
          "end_at" = case when v_change -> 'value' ? 'endAt' then (v_change -> 'value' ->> 'endAt')::timestamptz else x."end_at" end
        where x."id" = v_item;
      when 'attachments' then
        select * into v_row from "better_supabase"."work_items" x where x."id" = v_item;
        if jsonb_typeof(coalesce((v_change -> 'value'), '[]'::jsonb)) <> 'array' then
      raise exception 'attachments must be a list of attachment ids' using errcode = '22023', hint = 'TASK_ATTACHMENTS_INVALID';
    end if;
    if jsonb_array_length(coalesce((v_change -> 'value'), '[]'::jsonb)) > 0 then
      update "better_supabase"."attachments" f set "subject_type" = 'work_item', "subject_id" = v_row."id"::text
      where f."id" = any (array(select jsonb_array_elements_text((v_change -> 'value'))::uuid))
        and f."organization_id" = v_row."tenant_id"
        and (f."subject_type" is null or (f."subject_type" = 'work_item' and f."subject_id" = v_row."id"::text))
        and ((auth.role() = 'service_role') or f."uploaded_by" = auth.uid());
      get diagnostics v_linked = row_count;
      if v_linked <> (select count(distinct x) from jsonb_array_elements_text((v_change -> 'value')) x) then
        raise exception 'attach only your own files in this organization that aren''t on another subject' using errcode = '22023', hint = 'TASK_ATTACHMENTS_INVALID';
      end if;
    end if;
      else
        raise exception 'that field can''t be written' using errcode = '22023', hint = 'TASK_FIELD_UNKNOWN';
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
      if update_work_items.atomic then
        raise;
      end if;
      get stacked diagnostics v_hint = pg_exception_hint, v_reason = message_text;
      v_rejected := v_rejected || jsonb_build_array(jsonb_build_object('workItemId', v_change ->> 'workItemId', 'field', v_field, 'hint', nullif(v_hint, ''), 'reason', v_reason));
    end;
  end loop;
  for v_row in select * from "better_supabase"."work_items" x where x."id" = any (v_touched) loop
    perform "better_supabase".emit_event('task.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'fields', (select jsonb_agg(distinct a ->> 'field') from jsonb_array_elements(v_accepted) a where (a ->> 'workItemId')::uuid = v_row."id")), 'work-items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  end loop;
  return jsonb_build_object('accepted', v_accepted, 'rejected', v_rejected);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.verify_organization_domain (
  id    uuid,
  actor uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."organization_domains";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role verifies domains' using errcode = '42501', hint = 'SSO_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."organization_domains" x where x."id" = verify_organization_domain.id for update;
  if v_row."id" is null or not (verify_organization_domain.actor is null or coalesce(better_supabase.can_user(verify_organization_domain.actor, 'tenant', v_row."organization_id", 'sso.manage'), false)) then
    raise exception 'No domain you manage has this id' using errcode = 'P0002', hint = 'SSO_DOMAIN_NOT_FOUND';
  end if;
  if v_row."verified_at" is not null then
    return to_jsonb(v_row) - 'verification_token' || jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."domain", 'value', 'better-supabase-domain-verification=' || v_row."verification_token"));
  end if;
  if exists (select 1 from "better_supabase"."organization_domains" x where x."domain" = v_row."domain" and x."verified_at" is not null) then
    raise exception 'Another organization has verified %', v_row."domain" using errcode = '23505', hint = 'SSO_DOMAIN_TAKEN';
  end if;
  update "better_supabase"."organization_domains" x set "verified_at" = now() where x."id" = v_row."id" returning * into v_row;
  perform "better_supabase".emit_event('sso_domain.verified', jsonb_build_object('organizationId', v_row."organization_id"::text, 'domainId', v_row."id", 'domain', v_row."domain", 'userId', verify_organization_domain.actor), 'organizations/' || v_row."organization_id"::text, (v_row."organization_id")::text, null, 'better-supabase/sso');
  perform better_supabase.audit_event(
    event_type => 'sso_domain.verified',
    category => 'security',
    target_type => 'domain',
    record_id => v_row."id"::text,
    target_label => v_row."domain",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'domainId', v_row."id", 'domain', v_row."domain", 'userId', verify_organization_domain.actor),
    actor_id => verify_organization_domain.actor
  );
  return to_jsonb(v_row) - 'verification_token' || jsonb_build_object('record', jsonb_build_object('type', 'TXT', 'name', '_better-supabase.' || v_row."domain", 'value', 'better-supabase-domain-verification=' || v_row."verification_token"));
end;
$function$;
