SET local check_function_bodies = off;

DROP TRIGGER "bsb_search_activity_index" ON "better_supabase"."activities";

DROP FUNCTION "api"."activities_of"(text, text, text[], timestamp WITH time zone, integer);

DROP FUNCTION "api"."delete_activity"(uuid);

DROP FUNCTION "api"."delete_time_entry"(uuid);

DROP FUNCTION "api"."list_time_entries"(uuid, uuid, timestamp WITH time zone, timestamp WITH time zone, text, text, boolean, integer);

DROP FUNCTION "better_supabase"."activities_of"(text, text, text[], timestamp WITH time zone, integer);

DROP FUNCTION "better_supabase"."delete_activity"(uuid);

DROP FUNCTION "better_supabase"."list_time_entries"(uuid, uuid, timestamp WITH time zone, timestamp WITH time zone, text, text, boolean, integer);

ALTER TABLE "better_supabase"."activities"
  ADD COLUMN "archived_at" timestamp WITH time zone;

CREATE OR REPLACE FUNCTION api.activities_of (
  subject_type text,
  subject_id   text,
  types        text[],
  before       timestamp with time zone,
  page_size    integer,
  archived     boolean                  DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."activities_of"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION api.archive_activity (
  activity uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."archive_activity"($1) $function$;

CREATE OR REPLACE FUNCTION api.archive_time_entry (
  entry_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."archive_time_entry"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_time_entries (
  tenant       uuid,
  user_id      uuid                     DEFAULT NULL::uuid,
  starts       timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  ends         timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  subject_type text                     DEFAULT NULL::text,
  subject_id   text                     DEFAULT NULL::text,
  everyone     boolean                  DEFAULT false,
  page_size    integer                  DEFAULT 200,
  archived     boolean                  DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_time_entries"($1, $2, $3, $4, $5, $6, $7, $8, $9) $function$;

CREATE OR REPLACE FUNCTION api.purge_activity (
  activity uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."purge_activity"($1) $function$;

CREATE OR REPLACE FUNCTION api.purge_time_entry (
  entry_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."purge_time_entry"($1) $function$;

CREATE OR REPLACE FUNCTION api.restore_activity (
  activity uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."restore_activity"($1) $function$;

CREATE OR REPLACE FUNCTION api.restore_time_entry (
  entry_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."restore_time_entry"($1) $function$;

CREATE OR REPLACE FUNCTION better_supabase.activities_of (
  subject_type text,
  subject_id   text,
  types        text[],
  before       timestamp with time zone,
  page_size    integer,
  archived     boolean                  DEFAULT false
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_rows jsonb;
begin
  select coalesce(jsonb_agg(p.value order by p.at desc, p.id desc), '[]'::jsonb) into v_rows
  from (
    select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."activity_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) as value, coalesce(x."done_at", x."due_at", x."created_at") as at, x."id" as id
    from "better_supabase"."activities" x
    join "better_supabase"."activity_subjects" k on k."activity_id" = x."id"
    where k."subject_type" = activities_of.subject_type and k."subject_id" = activities_of.subject_id
      and (activities_of.types is null or x."type" = any (activities_of.types))
      and (activities_of.before is null or coalesce(x."done_at", x."due_at", x."created_at") < activities_of.before)
      and ((x."archived_at" is not null) = coalesce(activities_of.archived, false))
    order by at desc, id desc
    limit least(greatest(coalesce(activities_of.page_size, 50), 1), 200)
  ) p;
  if jsonb_array_length(v_rows) > 0 then
    perform "better_supabase"."record_subject_read"(activities_of.subject_type, activities_of.subject_id, null, 'activities', 'activities_of');
  end if;
  return v_rows;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.amend_activity (
  activity uuid,
  body     text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_from "better_supabase"."activities";
  v_id uuid;
  v_body text := nullif(trim(amend_activity.body), '');
  v_subjects jsonb;
  v_first jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_from from "better_supabase"."activities" x
  where x."id" = amend_activity.activity and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or x."tenant_id" in (select better_supabase.tenant_ids_with('activities.read')) and (
  not exists (select 1 from "better_supabase"."activity_subjects" lx where lx."activity_id" = x."id")
  or exists (select 1 from "better_supabase"."activity_subjects" lx where lx."activity_id" = x."id" and "better_supabase"."can_subject"(lx."subject_type", lx."subject_id", 'read'))
) and (x."audience" <> 'restricted' or x."tenant_id" in (select better_supabase.tenant_ids_with('activities.read_restricted')) or x."owner_id" = (select auth.uid()) or x."created_by" = (select auth.uid()) or exists (select 1 from "better_supabase"."activity_subjects" nx where nx."activity_id" = x."id" and "better_supabase"."has_subject_role"(nx."subject_type", nx."subject_id", x."restricted_roles"))));
  if v_from."id" is null then
    raise exception 'no such activity you can read' using errcode = 'P0002', hint = 'ACTIVITY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_from."tenant_id", 'activities.write'), false)) then
    raise exception 'not allowed to amend activities' using errcode = '42501', hint = 'ACTIVITY_FORBIDDEN';
  end if;
  if v_from."archived_at" is not null then
    raise exception 'the activity is archived: restore it first' using errcode = '55000', hint = 'ACTIVITY_ARCHIVED';
  end if;
  if v_body is null then
    raise exception 'an addendum needs a body' using errcode = '23502', hint = 'ACTIVITY_BODY_REQUIRED';
  end if;
  insert into "better_supabase"."activities" ("tenant_id", "type", "title", "body", "owner_id", "amends_id", "audience", "restricted_roles", "category", "goal_id", "locked_at", "created_by")
  values (v_from."tenant_id", v_from."type", v_from."title", v_body, auth.uid(), v_from."id", v_from."audience", v_from."restricted_roles", v_from."category", v_from."goal_id", case when v_from."type"::text = any ('{note,report}'::text[]) then now() + interval '24 hours' end, auth.uid())
  returning "id" into v_id;
  insert into "better_supabase"."activity_subjects" ("tenant_id", "activity_id", "subject_type", "subject_id", "position")
  select k."tenant_id", v_id, k."subject_type", k."subject_id", k."position"
  from "better_supabase"."activity_subjects" k where k."activity_id" = v_from."id";
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."activity_subjects" sx where sx."activity_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  perform "better_supabase".emit_event('activity.amended', jsonb_build_object('organizationId', v_from."tenant_id", 'activityId', v_id, 'type', v_from."type"::text, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects, 'amendsId', v_from."id"), 'activities/' || v_id::text, (v_from."tenant_id"::text)::text, null, 'better-supabase/activities');
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."activity_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."activities" x where x."id" = v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.archive_activity (
  activity uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."activities";
  v_id uuid;
  v_tenant uuid;
  v_type text;
  v_subjects jsonb;
  v_first jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  v_id := archive_activity.activity;
  select * into v_row from "better_supabase"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) for update;
  if v_row."id" is null then
    raise exception 'no such activity you can edit' using errcode = 'P0002', hint = 'ACTIVITY_NOT_FOUND';
  end if;
  v_tenant := v_row."tenant_id";
  v_type := v_row."type";
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."activity_subjects" sx where sx."activity_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  if v_row."archived_at" is not null then
    return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."activity_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."activities" x where x."id" = v_id);
  end if;
  if exists (select 1 from "better_supabase"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the activity is locked: add an addendum with amend_activity instead' using errcode = '55000', hint = 'ACTIVITY_LOCKED';
  end if;
  update "better_supabase"."activities" x set
    "archived_at" = now(),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('activity.archived', jsonb_build_object('organizationId', v_tenant, 'activityId', v_id, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects), 'activities/' || v_id::text, (v_tenant::text)::text, null, 'better-supabase/activities');
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."activity_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."activities" x where x."id" = v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.archive_time_entry (
  entry_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."time_entries"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."time_entries" x where x."id" = archive_time_entry.entry_id for update;
  if not found then
    raise exception 'time entry not found' using errcode = 'P0002', hint = 'TIME_ENTRY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(v_row."user_id" = auth.uid(), false) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'time_entries.track'), false)) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'time_entries.manage'), false)) then
    raise exception 'not allowed to change this entry' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if v_row."archived_at" is not null then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
  end if;
  if v_row."ended_at" is null then
    raise exception 'stop the running timer before archiving it' using errcode = '55000', hint = 'TIME_TIMER_RUNNING';
  end if;
  update "better_supabase"."time_entries" x set
    "archived_at" = now(),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('time_entry.archived', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'id', v_row."id", 'userId', v_row."user_id", 'startedAt', v_row."started_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency"), 'time-entries/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/time-entries');
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.attach_activity_recording (
  activity uuid,
  file     uuid,
  language text
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
  from "better_supabase"."activities" x where x."id" = attach_activity_recording.activity and ((auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and x."archived_at" is null);
  if v_tenant is null then
    raise exception 'no such activity you can edit' using errcode = 'P0002', hint = 'ACTIVITY_NOT_FOUND';
  end if;
  if not exists (
    select 1 from "better_supabase"."ai_files" fx
    where fx."id" = attach_activity_recording.file
      and fx."tenant_id"::text = v_tenant::text
      and fx."status" = 'ready'
      and (auth.role() = 'service_role' or fx."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_tenant, 'activities.manage'), false))
  ) then
    raise exception 'no such ready file in this organization' using errcode = 'P0002', hint = 'AI_FILE_NOT_FOUND';
  end if;
  insert into "better_supabase"."activity_recordings" ("tenant_id", "activity_id", "file_id", "filename", "media_type", "language", "created_by")
  select v_tenant, attach_activity_recording.activity, fx."id", fx."filename", fx."media_type", nullif(trim(attach_activity_recording.language), ''), auth.uid()
  from "better_supabase"."ai_files" fx where fx."id" = attach_activity_recording.file
  on conflict ("activity_id", "file_id") do nothing
  returning "id" into v_recording;
  if v_recording is null then
    raise exception 'the file is already a recording of this activity' using errcode = '23505', hint = 'ACTIVITY_RECORDING_EXISTS';
  end if;
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."activity_subjects" sx where sx."activity_id" = attach_activity_recording.activity), '[]'::jsonb);
  v_first := v_subjects -> 0;
  perform "better_supabase".emit_event('activity.recorded', jsonb_build_object('organizationId', v_tenant, 'activityId', attach_activity_recording.activity, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects, 'recordingId', v_recording), 'activities/' || attach_activity_recording.activity::text, (v_tenant::text)::text, null, 'better-supabase/activities');
  perform "better_supabase"."enqueue_job"(queue => 'activities.transcribe', payload => jsonb_build_object('recordingId', v_recording), dedupe_key => 'activities.transcribe:' || v_recording::text, dedupe_running => false);
  return (select jsonb_build_object('id', rx."id", 'organizationId', rx."tenant_id", 'activityId', rx."activity_id", 'fileId', rx."file_id", 'filename', rx."filename", 'mediaType', rx."media_type", 'status', rx."status", 'language', rx."language", 'durationSeconds', rx."duration_seconds", 'error', rx."error", 'model', rx."model", 'segmentCount', (select count(*)::integer from "better_supabase"."activity_transcript_segments" sc where sc."recording_id" = rx."id"), 'createdBy', rx."created_by", 'createdAt', rx."created_at", 'transcribedAt', rx."transcribed_at") from "better_supabase"."activity_recordings" rx where rx."id" = v_recording);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.billable_time_guard()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not exists (select 1 from "better_supabase"."time_invoice_entries" d where d."entry_id" = old."id") then
    if tg_op = 'DELETE' then
      return old;
    end if;
    return new;
  end if;
  -- restrict_violation, so an organization purge retries the table later.
  if tg_op = 'DELETE' then
    raise exception 'this entry is on an invoice; void the invoice to delete it' using errcode = '23001', hint = 'TIME_ENTRY_INVOICED';
  end if;
  if old."started_at" is distinct from new."started_at" or old."ended_at" is distinct from new."ended_at" or old."billable" is distinct from new."billable" or old."rate" is distinct from new."rate" or old."rate_currency" is distinct from new."rate_currency" or old."archived_at" is distinct from new."archived_at" then
    raise exception 'this entry is on an invoice; void the invoice to change it' using errcode = '55000', hint = 'TIME_ENTRY_INVOICED';
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.can_subject (
  subject_type text,
  subject_id   text,
  action       text
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  COST 1000
  SET search_path TO ''
  AS $function$
begin
  case can_subject.subject_type
    when 'message' then
      return exists (
        select 1 from "better_supabase"."messages" s
        where s."id" = (can_subject.subject_id)::uuid and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'messages.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'messages.send'), false)
          when 'upload' then coalesce(better_supabase.can('tenant', s."tenant_id", 'messages.send'), false)
          else true
        end)
      );
    when 'conversation' then
      return exists (
        select 1 from "better_supabase"."conversations" s
        where s."id" = (can_subject.subject_id)::uuid and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'messages.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'messages.send'), false)
          when 'upload' then coalesce(better_supabase.can('tenant', s."tenant_id", 'messages.send'), false)
          else true
        end)
      );
    when 'channel' then
      return exists (
        select 1 from "better_supabase"."channels" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'messages.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'channels.manage'), false)
          else true
        end)
      );
    when 'company' then
      return exists (
        select 1 from "better_supabase"."companies" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'contacts.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'contacts.write'), false)
          else true
        end)
      );
    when 'person' then
      return exists (
        select 1 from "better_supabase"."people" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'contacts.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'contacts.write'), false)
          else true
        end)
      );
    when 'deal' then
      return exists (
        select 1 from "better_supabase"."deals" s
        where s."id" = (can_subject.subject_id)::uuid and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'deals.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'deals.write'), false)
          else true
        end)
      );
    when 'course' then
      return exists (
        select 1 from "better_supabase"."courses" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'courses.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'courses.manage'), false)
          else true
        end)
      );
    when 'post' then
      return exists (
        select 1 from "better_supabase"."posts" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'posts.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'posts.write'), false)
          else true
        end)
      );
    when 'activity' then
      return exists (
        select 1 from "better_supabase"."activities" s
        where s."id" = (can_subject.subject_id)::uuid and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'activities.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'activities.write'), false)
          else true
        end)
      );
    when 'quote' then
      return exists (
        select 1 from "better_supabase"."quotes" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'quotes.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'quotes.write'), false)
          else true
        end)
      );
    when 'work_item' then
      return exists (
        select 1 from "better_supabase"."work_items" s
        where s."id" = (can_subject.subject_id)::uuid and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'tasks.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'tasks.write'), false)
          else true
        end)
      );
    when 'employee' then
      return exists (
        select 1 from "better_supabase"."employees" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'employees.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'employees.write'), false)
          else true
        end)
      );
    when 'ledger_account' then
      return exists (
        select 1 from "better_supabase"."ledger_accounts" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'ledger.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'ledger.manage'), false)
          else true
        end)
      );
    when 'invoice' then
      return exists (
        select 1 from "better_supabase"."invoices" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'invoices.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'invoices.write'), false)
          else true
        end)
      );
    when 'product' then
      return exists (
        select 1 from "better_supabase"."products" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'catalog.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'catalog.manage'), false)
          else true
        end)
      );
    when 'product_variant' then
      return exists (
        select 1 from "better_supabase"."product_variants" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'catalog.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'catalog.manage'), false)
          else true
        end)
      );
    when 'rfq' then
      return exists (
        select 1 from "better_supabase"."rfqs" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'rfqs.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'rfqs.write'), false)
          else true
        end)
      );
    when 'till' then
      return exists (
        select 1 from "better_supabase"."tills" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'tills.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'tills.write'), false)
          else true
        end)
      );
    when 'order' then
      return exists (
        select 1 from "better_supabase"."orders" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'orders.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'orders.manage'), false)
          else true
        end)
      );
    when 'calendar_event' then
      return exists (
        select 1 from "better_supabase"."calendar_events" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'calendar.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'calendar.write'), false)
          else true
        end)
      );
    when 'booking' then
      return exists (
        select 1 from "better_supabase"."bookings" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'bookings.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'bookings.manage'), false)
          else true
        end)
      );
    when 'asset' then
      return exists (
        select 1 from "better_supabase"."assets" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'assets.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'assets.manage'), false)
          else true
        end)
      );
    when 'asset_location' then
      return exists (
        select 1 from "better_supabase"."asset_locations" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'assets.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'assets.manage'), false)
          else true
        end)
      );
    when 'lease' then
      return exists (
        select 1 from "better_supabase"."leases" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'leases.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'leases.manage'), false)
          else true
        end)
      );
    when 'expense_report' then
      return exists (
        select 1 from "better_supabase"."expense_reports" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'expenses.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'expenses.manage'), false)
          else true
        end)
      );
    when 'expense_line' then
      return exists (
        select 1 from "better_supabase"."expense_lines" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'expenses.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'expenses.manage'), false)
          when 'upload' then coalesce(better_supabase.can('tenant', s."tenant_id", 'expenses.submit'), false)
          else true
        end)
      );
    when 'donation_fund' then
      return exists (
        select 1 from "better_supabase"."donation_funds" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'donations.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'donations.manage'), false)
          else true
        end)
      );
    when 'warranty_claim' then
      return exists (
        select 1 from "better_supabase"."warranty_claims" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'warranty.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'warranty.write'), false)
          when 'upload' then coalesce(better_supabase.can('tenant', s."tenant_id", 'warranty.write'), false)
          else true
        end)
      );
    when 'work_order' then
      return exists (
        select 1 from "better_supabase"."work_orders" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'dispatch.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'dispatch.manage'), false)
          else true
        end)
      );
    when 'shipment' then
      return exists (
        select 1 from "better_supabase"."shipments" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'shipments.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'shipments.manage'), false)
          else true
        end)
      );
    when 'contract' then
      return exists (
        select 1 from "better_supabase"."contracts" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'contracts.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'contracts.write'), false)
          else true
        end)
      );
    when 'control' then
      return exists (
        select 1 from "better_supabase"."controls" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'compliance.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'compliance.manage'), false)
          else true
        end)
      );
    when 'compliance_policy' then
      return exists (
        select 1 from "better_supabase"."compliance_policies" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'compliance.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'compliance.manage'), false)
          else true
        end)
      );
    when 'qualification_type' then
      return exists (
        select 1 from "better_supabase"."qualification_types" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'qualifications.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'qualifications.manage'), false)
          else true
        end)
      );
    when 'risk' then
      return exists (
        select 1 from "better_supabase"."risks" s
        where s."id" = (can_subject.subject_id)::uuid and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'risks.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'risks.write'), false)
          else true
        end)
      );
    when 'case' then
      return exists (
        select 1 from "better_supabase"."cases" s
        where s."id" = (can_subject.subject_id)::uuid and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'cases.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'cases.write'), false)
          else true
        end)
      );
    when 'inspection' then
      return exists (
        select 1 from "better_supabase"."inspections" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'inspections.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'inspections.write'), false)
          else true
        end)
      );
    when 'inspection_program' then
      return exists (
        select 1 from "better_supabase"."inspection_programs" s
        where s."id" = (can_subject.subject_id)::uuid and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'inspections.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'inspections.manage'), false)
          else true
        end)
      );
    when 'inspection_finding' then
      return exists (
        select 1 from "better_supabase"."inspection_findings" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'inspections.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'inspections.write'), false)
          else true
        end)
      );
    when 'form' then
      return exists (
        select 1 from "better_supabase"."forms" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'forms.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'forms.manage'), false)
          else true
        end)
      );
    when 'meeting' then
      return exists (
        select 1 from "better_supabase"."meetings" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'meetings.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'meetings.write'), false)
          else true
        end)
      );
    when 'meeting_decision' then
      return exists (
        select 1 from "better_supabase"."meeting_decisions" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'meetings.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'meetings.write'), false)
          else true
        end)
      );
    when 'maintenance_plan' then
      return exists (
        select 1 from "better_supabase"."maintenance_plans" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'maintenance.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'maintenance.manage'), false)
          else true
        end)
      );
    when 'dam_usage_right' then
      return exists (
        select 1 from "better_supabase"."dam_usage_rights" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'dam.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'dam.write'), false)
          else true
        end)
      );
    when 'lims_sample' then
      return exists (
        select 1 from "better_supabase"."lims_samples" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'lims.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'lims.write'), false)
          else true
        end)
      );
    when 'tax_code' then
      return exists (
        select 1 from "better_supabase"."tax_codes" s
        where s."id" = (can_subject.subject_id)::uuid and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'tax.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'tax.manage'), false)
          else true
        end)
      );
    when 'production_order' then
      return exists (
        select 1 from "better_supabase"."production_orders" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'manufacturing.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'manufacturing.write'), false)
          else true
        end)
      );
    when 'work_center' then
      return exists (
        select 1 from "better_supabase"."work_centers" s
        where s."id" = (can_subject.subject_id)::uuid and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'manufacturing.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'manufacturing.manage'), false)
          else true
        end)
      );
    when 'bank_account' then
      return exists (
        select 1 from "better_supabase"."bank_accounts" s
        where s."id" = (can_subject.subject_id)::uuid and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'banking.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'banking.manage'), false)
          else true
        end)
      );
    when 'care_plan' then
      return exists (
        select 1 from "better_supabase"."care_plans" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'care_plans.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'care_plans.write'), false)
          else true
        end)
      );
    when 'incident' then
      return exists (
        select 1 from "better_supabase"."incidents" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'incidents.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'incidents.write'), false)
          else true
        end)
      );
    when 'advisory' then
      return exists (
        select 1 from "better_supabase"."advisories" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'advisories.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'advisories.write'), false)
          else true
        end)
      );
    when 'advisory_product' then
      return exists (
        select 1 from "better_supabase"."advisory_products" s
        where s."id" = (can_subject.subject_id)::uuid and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'advisories.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'advisories.write'), false)
          else true
        end)
      );
    when 'vulnerability' then
      return exists (
        select 1 from "better_supabase"."vulnerabilities" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'advisories.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'advisories.write'), false)
          else true
        end)
      );
    when 'content_entry' then
      return exists (
        select 1 from "better_supabase"."content_entries" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'content.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'content.write'), false)
          else true
        end)
      );
    when 'document' then
      return exists (
        select 1 from "better_supabase"."documents" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'documents.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'documents.write'), false)
          else true
        end)
      );
    when 'customer' then
      return exists (
        select 1 from "public"."customers" s
        where s."id" = (can_subject.subject_id)::uuid and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then (coalesce(better_supabase.can('tenant', s."organization_id", 'customers.read'), false) or "better_supabase"."is_subject_member"('customer', s."id"::text))
          when 'write' then (coalesce(better_supabase.can('tenant', s."organization_id", 'customers.write'), false) or "better_supabase"."is_subject_member"('customer', s."id"::text))
          else true
        end)
      );
    when 'drive_node' then
      return exists (
        select 1 from "better_supabase"."drive_nodes" s
        where s."id" = (can_subject.subject_id)::uuid and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then ((coalesce(better_supabase.can('tenant', s."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)) or "better_supabase"."is_subject_member"('drive_node', s."id"::text))
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'drive.manage'), false)
          when 'comment' then coalesce("better_supabase"."drive_can_comment"(s."id"), false)
          when 'fields' then coalesce("better_supabase"."drive_node_writable"(s."id"), false)
          else true
        end)
      );
    when 'organization' then
      return exists (
        select 1 from "public"."organizations" s
        where s."id" = (can_subject.subject_id)::uuid
          and true
      );
    when 'application' then
      return exists (
        select 1 from "better_supabase"."applications" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'hiring.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'hiring.write'), false)
          else true
        end)
      );
    when 'change_request' then
      return exists (
        select 1 from "public"."change_requests" s
        where s."id" = (can_subject.subject_id)::uuid
          and true
      );
    when 'project' then
      return exists (
        select 1 from "public"."projects" s
        where s."id" = (can_subject.subject_id)::uuid and s."deleted_at" is null
          and true
      );
    when 'task' then
      return exists (
        select 1 from "public"."tasks" s
        where s."id" = (can_subject.subject_id)::uuid
          and true
      );
    else
      return false;
  end case;
  return false;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.can_subject_for (
  member       uuid,
  subject_type text,
  subject_id   text,
  action       text
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  case can_subject_for.subject_type
    when 'message' then
      return exists (
        select 1 from "better_supabase"."messages" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."archived_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'messages.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'messages.send'), false)
          when 'upload' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'messages.send'), false)
          else false
        end
      );
    when 'conversation' then
      return exists (
        select 1 from "better_supabase"."conversations" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."archived_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'messages.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'messages.send'), false)
          when 'upload' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'messages.send'), false)
          else false
        end
      );
    when 'channel' then
      return exists (
        select 1 from "better_supabase"."channels" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'messages.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'channels.manage'), false)
          else false
        end
      );
    when 'company' then
      return exists (
        select 1 from "better_supabase"."companies" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'contacts.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'contacts.write'), false)
          else false
        end
      );
    when 'person' then
      return exists (
        select 1 from "better_supabase"."people" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'contacts.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'contacts.write'), false)
          else false
        end
      );
    when 'deal' then
      return exists (
        select 1 from "better_supabase"."deals" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."archived_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'deals.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'deals.write'), false)
          else false
        end
      );
    when 'course' then
      return exists (
        select 1 from "better_supabase"."courses" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'courses.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'courses.manage'), false)
          else false
        end
      );
    when 'post' then
      return exists (
        select 1 from "better_supabase"."posts" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'posts.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'posts.write'), false)
          else false
        end
      );
    when 'activity' then
      return exists (
        select 1 from "better_supabase"."activities" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."archived_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'activities.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'activities.write'), false)
          else false
        end
      );
    when 'quote' then
      return exists (
        select 1 from "better_supabase"."quotes" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'quotes.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'quotes.write'), false)
          else false
        end
      );
    when 'work_item' then
      return exists (
        select 1 from "better_supabase"."work_items" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."archived_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'tasks.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'tasks.write'), false)
          else false
        end
      );
    when 'employee' then
      return exists (
        select 1 from "better_supabase"."employees" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'employees.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'employees.write'), false)
          else false
        end
      );
    when 'ledger_account' then
      return exists (
        select 1 from "better_supabase"."ledger_accounts" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'ledger.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'ledger.manage'), false)
          else false
        end
      );
    when 'invoice' then
      return exists (
        select 1 from "better_supabase"."invoices" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'invoices.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'invoices.write'), false)
          else false
        end
      );
    when 'product' then
      return exists (
        select 1 from "better_supabase"."products" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'catalog.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'catalog.manage'), false)
          else false
        end
      );
    when 'product_variant' then
      return exists (
        select 1 from "better_supabase"."product_variants" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'catalog.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'catalog.manage'), false)
          else false
        end
      );
    when 'rfq' then
      return exists (
        select 1 from "better_supabase"."rfqs" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'rfqs.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'rfqs.write'), false)
          else false
        end
      );
    when 'till' then
      return exists (
        select 1 from "better_supabase"."tills" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'tills.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'tills.write'), false)
          else false
        end
      );
    when 'order' then
      return exists (
        select 1 from "better_supabase"."orders" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'orders.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'orders.manage'), false)
          else false
        end
      );
    when 'calendar_event' then
      return exists (
        select 1 from "better_supabase"."calendar_events" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'calendar.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'calendar.write'), false)
          else false
        end
      );
    when 'booking' then
      return exists (
        select 1 from "better_supabase"."bookings" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'bookings.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'bookings.manage'), false)
          else false
        end
      );
    when 'asset' then
      return exists (
        select 1 from "better_supabase"."assets" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'assets.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'assets.manage'), false)
          else false
        end
      );
    when 'asset_location' then
      return exists (
        select 1 from "better_supabase"."asset_locations" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'assets.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'assets.manage'), false)
          else false
        end
      );
    when 'lease' then
      return exists (
        select 1 from "better_supabase"."leases" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'leases.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'leases.manage'), false)
          else false
        end
      );
    when 'expense_report' then
      return exists (
        select 1 from "better_supabase"."expense_reports" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'expenses.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'expenses.manage'), false)
          else false
        end
      );
    when 'expense_line' then
      return exists (
        select 1 from "better_supabase"."expense_lines" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'expenses.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'expenses.manage'), false)
          when 'upload' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'expenses.submit'), false)
          else false
        end
      );
    when 'donation_fund' then
      return exists (
        select 1 from "better_supabase"."donation_funds" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'donations.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'donations.manage'), false)
          else false
        end
      );
    when 'warranty_claim' then
      return exists (
        select 1 from "better_supabase"."warranty_claims" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'warranty.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'warranty.write'), false)
          when 'upload' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'warranty.write'), false)
          else false
        end
      );
    when 'work_order' then
      return exists (
        select 1 from "better_supabase"."work_orders" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'dispatch.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'dispatch.manage'), false)
          else false
        end
      );
    when 'shipment' then
      return exists (
        select 1 from "better_supabase"."shipments" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'shipments.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'shipments.manage'), false)
          else false
        end
      );
    when 'contract' then
      return exists (
        select 1 from "better_supabase"."contracts" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'contracts.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'contracts.write'), false)
          else false
        end
      );
    when 'control' then
      return exists (
        select 1 from "better_supabase"."controls" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'compliance.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'compliance.manage'), false)
          else false
        end
      );
    when 'compliance_policy' then
      return exists (
        select 1 from "better_supabase"."compliance_policies" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'compliance.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'compliance.manage'), false)
          else false
        end
      );
    when 'qualification_type' then
      return exists (
        select 1 from "better_supabase"."qualification_types" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'qualifications.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'qualifications.manage'), false)
          else false
        end
      );
    when 'risk' then
      return exists (
        select 1 from "better_supabase"."risks" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."archived_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'risks.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'risks.write'), false)
          else false
        end
      );
    when 'case' then
      return exists (
        select 1 from "better_supabase"."cases" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."archived_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'cases.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'cases.write'), false)
          else false
        end
      );
    when 'inspection' then
      return exists (
        select 1 from "better_supabase"."inspections" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'inspections.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'inspections.write'), false)
          else false
        end
      );
    when 'inspection_program' then
      return exists (
        select 1 from "better_supabase"."inspection_programs" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."archived_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'inspections.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'inspections.manage'), false)
          else false
        end
      );
    when 'inspection_finding' then
      return exists (
        select 1 from "better_supabase"."inspection_findings" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'inspections.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'inspections.write'), false)
          else false
        end
      );
    when 'form' then
      return exists (
        select 1 from "better_supabase"."forms" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'forms.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'forms.manage'), false)
          else false
        end
      );
    when 'meeting' then
      return exists (
        select 1 from "better_supabase"."meetings" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'meetings.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'meetings.write'), false)
          else false
        end
      );
    when 'meeting_decision' then
      return exists (
        select 1 from "better_supabase"."meeting_decisions" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'meetings.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'meetings.write'), false)
          else false
        end
      );
    when 'maintenance_plan' then
      return exists (
        select 1 from "better_supabase"."maintenance_plans" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'maintenance.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'maintenance.manage'), false)
          else false
        end
      );
    when 'dam_usage_right' then
      return exists (
        select 1 from "better_supabase"."dam_usage_rights" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'dam.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'dam.write'), false)
          else false
        end
      );
    when 'lims_sample' then
      return exists (
        select 1 from "better_supabase"."lims_samples" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'lims.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'lims.write'), false)
          else false
        end
      );
    when 'tax_code' then
      return exists (
        select 1 from "better_supabase"."tax_codes" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."archived_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'tax.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'tax.manage'), false)
          else false
        end
      );
    when 'production_order' then
      return exists (
        select 1 from "better_supabase"."production_orders" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'manufacturing.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'manufacturing.write'), false)
          else false
        end
      );
    when 'work_center' then
      return exists (
        select 1 from "better_supabase"."work_centers" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."archived_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'manufacturing.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'manufacturing.manage'), false)
          else false
        end
      );
    when 'bank_account' then
      return exists (
        select 1 from "better_supabase"."bank_accounts" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."archived_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'banking.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'banking.manage'), false)
          else false
        end
      );
    when 'care_plan' then
      return exists (
        select 1 from "better_supabase"."care_plans" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'care_plans.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'care_plans.write'), false)
          else false
        end
      );
    when 'incident' then
      return exists (
        select 1 from "better_supabase"."incidents" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'incidents.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'incidents.write'), false)
          else false
        end
      );
    when 'advisory' then
      return exists (
        select 1 from "better_supabase"."advisories" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'advisories.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'advisories.write'), false)
          else false
        end
      );
    when 'advisory_product' then
      return exists (
        select 1 from "better_supabase"."advisory_products" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."archived_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'advisories.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'advisories.write'), false)
          else false
        end
      );
    when 'vulnerability' then
      return exists (
        select 1 from "better_supabase"."vulnerabilities" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'advisories.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'advisories.write'), false)
          else false
        end
      );
    when 'content_entry' then
      return exists (
        select 1 from "better_supabase"."content_entries" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'content.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'content.write'), false)
          else false
        end
      );
    when 'document' then
      return exists (
        select 1 from "better_supabase"."documents" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'documents.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'documents.write'), false)
          else false
        end
      );
    when 'customer' then
      return exists (
        select 1 from "public"."customers" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."archived_at" is null
          and case can_subject_for.action
          when 'read' then (coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."organization_id", 'customers.read'), false) or exists (
            select 1 from "better_supabase"."subject_members" m
            where m."subject_type" = 'customer'
              and m."subject_id" = s."id"::text
              and m."tenant_id" = s."organization_id"
              and (m."user_id" = can_subject_for.member or (m."team_id" is not null and exists (
          select 1 from "better_supabase"."team_members" tm
          where tm."team_id" = m."team_id"
            and tm."user_id" = can_subject_for.member)))
        and (m."starts_on" is null or m."starts_on" <= current_date)
        and (m."ends_on" is null or m."ends_on" >= current_date)
        and (m."ends_at" is null or m."ends_at" > now())))
          when 'write' then (coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."organization_id", 'customers.write'), false) or exists (
            select 1 from "better_supabase"."subject_members" m
            where m."subject_type" = 'customer'
              and m."subject_id" = s."id"::text
              and m."tenant_id" = s."organization_id"
              and (m."user_id" = can_subject_for.member or (m."team_id" is not null and exists (
          select 1 from "better_supabase"."team_members" tm
          where tm."team_id" = m."team_id"
            and tm."user_id" = can_subject_for.member)))
        and (m."starts_on" is null or m."starts_on" <= current_date)
        and (m."ends_on" is null or m."ends_on" >= current_date)
        and (m."ends_at" is null or m."ends_at" > now())))
          else false
        end
      );
    when 'drive_node' then
      return exists (
        select 1 from "better_supabase"."drive_nodes" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."archived_at" is null
          and case can_subject_for.action
          when 'read' then (false or exists (
            select 1 from "better_supabase"."subject_members" m
            where m."subject_type" = 'drive_node'
              and m."subject_id" = s."id"::text
              and m."tenant_id" = s."tenant_id"
              and (m."user_id" = can_subject_for.member or (m."team_id" is not null and exists (
          select 1 from "better_supabase"."team_members" tm
          where tm."team_id" = m."team_id"
            and tm."user_id" = can_subject_for.member)))
        and (m."starts_on" is null or m."starts_on" <= current_date)
        and (m."ends_on" is null or m."ends_on" >= current_date)
        and (m."ends_at" is null or m."ends_at" > now())))
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'drive.manage'), false)
          when 'comment' then false
          when 'fields' then false
          else false
        end
      );
    when 'organization' then
      return exists (
        select 1 from "public"."organizations" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and false
      );
    when 'application' then
      return exists (
        select 1 from "better_supabase"."applications" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'hiring.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'hiring.write'), false)
          else false
        end
      );
    when 'change_request' then
      return exists (
        select 1 from "public"."change_requests" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and false
      );
    when 'project' then
      return exists (
        select 1 from "public"."projects" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."deleted_at" is null
          and false
      );
    when 'task' then
      return exists (
        select 1 from "public"."tasks" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and false
      );
    else
      return false;
  end case;
  return false;
exception
  when feature_not_supported then
    return false;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.can_subjects (
  subject_type text,
  subject_ids  text[],
  action       text
)
  RETURNS SETOF text
  LANGUAGE plpgsql
  STABLE
  COST 1000
  SET search_path TO ''
  AS $function$
begin
  case can_subjects.subject_type
    when 'message' then
      return query
        select s."id"::text from "better_supabase"."messages" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[]) and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'messages.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'messages.send'), false)
          when 'upload' then coalesce(better_supabase.can('tenant', s."tenant_id", 'messages.send'), false)
          else true
        end);
    when 'conversation' then
      return query
        select s."id"::text from "better_supabase"."conversations" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[]) and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'messages.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'messages.send'), false)
          when 'upload' then coalesce(better_supabase.can('tenant', s."tenant_id", 'messages.send'), false)
          else true
        end);
    when 'channel' then
      return query
        select s."id"::text from "better_supabase"."channels" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'messages.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'channels.manage'), false)
          else true
        end);
    when 'company' then
      return query
        select s."id"::text from "better_supabase"."companies" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'contacts.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'contacts.write'), false)
          else true
        end);
    when 'person' then
      return query
        select s."id"::text from "better_supabase"."people" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'contacts.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'contacts.write'), false)
          else true
        end);
    when 'deal' then
      return query
        select s."id"::text from "better_supabase"."deals" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[]) and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'deals.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'deals.write'), false)
          else true
        end);
    when 'course' then
      return query
        select s."id"::text from "better_supabase"."courses" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'courses.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'courses.manage'), false)
          else true
        end);
    when 'post' then
      return query
        select s."id"::text from "better_supabase"."posts" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'posts.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'posts.write'), false)
          else true
        end);
    when 'activity' then
      return query
        select s."id"::text from "better_supabase"."activities" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[]) and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'activities.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'activities.write'), false)
          else true
        end);
    when 'quote' then
      return query
        select s."id"::text from "better_supabase"."quotes" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'quotes.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'quotes.write'), false)
          else true
        end);
    when 'work_item' then
      return query
        select s."id"::text from "better_supabase"."work_items" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[]) and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'tasks.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'tasks.write'), false)
          else true
        end);
    when 'employee' then
      return query
        select s."id"::text from "better_supabase"."employees" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'employees.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'employees.write'), false)
          else true
        end);
    when 'ledger_account' then
      return query
        select s."id"::text from "better_supabase"."ledger_accounts" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'ledger.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'ledger.manage'), false)
          else true
        end);
    when 'invoice' then
      return query
        select s."id"::text from "better_supabase"."invoices" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'invoices.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'invoices.write'), false)
          else true
        end);
    when 'product' then
      return query
        select s."id"::text from "better_supabase"."products" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'catalog.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'catalog.manage'), false)
          else true
        end);
    when 'product_variant' then
      return query
        select s."id"::text from "better_supabase"."product_variants" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'catalog.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'catalog.manage'), false)
          else true
        end);
    when 'rfq' then
      return query
        select s."id"::text from "better_supabase"."rfqs" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'rfqs.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'rfqs.write'), false)
          else true
        end);
    when 'till' then
      return query
        select s."id"::text from "better_supabase"."tills" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'tills.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'tills.write'), false)
          else true
        end);
    when 'order' then
      return query
        select s."id"::text from "better_supabase"."orders" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'orders.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'orders.manage'), false)
          else true
        end);
    when 'calendar_event' then
      return query
        select s."id"::text from "better_supabase"."calendar_events" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'calendar.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'calendar.write'), false)
          else true
        end);
    when 'booking' then
      return query
        select s."id"::text from "better_supabase"."bookings" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'bookings.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'bookings.manage'), false)
          else true
        end);
    when 'asset' then
      return query
        select s."id"::text from "better_supabase"."assets" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'assets.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'assets.manage'), false)
          else true
        end);
    when 'asset_location' then
      return query
        select s."id"::text from "better_supabase"."asset_locations" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'assets.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'assets.manage'), false)
          else true
        end);
    when 'lease' then
      return query
        select s."id"::text from "better_supabase"."leases" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'leases.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'leases.manage'), false)
          else true
        end);
    when 'expense_report' then
      return query
        select s."id"::text from "better_supabase"."expense_reports" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'expenses.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'expenses.manage'), false)
          else true
        end);
    when 'expense_line' then
      return query
        select s."id"::text from "better_supabase"."expense_lines" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'expenses.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'expenses.manage'), false)
          when 'upload' then coalesce(better_supabase.can('tenant', s."tenant_id", 'expenses.submit'), false)
          else true
        end);
    when 'donation_fund' then
      return query
        select s."id"::text from "better_supabase"."donation_funds" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'donations.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'donations.manage'), false)
          else true
        end);
    when 'warranty_claim' then
      return query
        select s."id"::text from "better_supabase"."warranty_claims" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'warranty.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'warranty.write'), false)
          when 'upload' then coalesce(better_supabase.can('tenant', s."tenant_id", 'warranty.write'), false)
          else true
        end);
    when 'work_order' then
      return query
        select s."id"::text from "better_supabase"."work_orders" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'dispatch.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'dispatch.manage'), false)
          else true
        end);
    when 'shipment' then
      return query
        select s."id"::text from "better_supabase"."shipments" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'shipments.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'shipments.manage'), false)
          else true
        end);
    when 'contract' then
      return query
        select s."id"::text from "better_supabase"."contracts" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'contracts.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'contracts.write'), false)
          else true
        end);
    when 'control' then
      return query
        select s."id"::text from "better_supabase"."controls" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'compliance.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'compliance.manage'), false)
          else true
        end);
    when 'compliance_policy' then
      return query
        select s."id"::text from "better_supabase"."compliance_policies" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'compliance.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'compliance.manage'), false)
          else true
        end);
    when 'qualification_type' then
      return query
        select s."id"::text from "better_supabase"."qualification_types" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'qualifications.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'qualifications.manage'), false)
          else true
        end);
    when 'risk' then
      return query
        select s."id"::text from "better_supabase"."risks" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[]) and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'risks.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'risks.write'), false)
          else true
        end);
    when 'case' then
      return query
        select s."id"::text from "better_supabase"."cases" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[]) and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'cases.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'cases.write'), false)
          else true
        end);
    when 'inspection' then
      return query
        select s."id"::text from "better_supabase"."inspections" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'inspections.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'inspections.write'), false)
          else true
        end);
    when 'inspection_program' then
      return query
        select s."id"::text from "better_supabase"."inspection_programs" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[]) and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'inspections.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'inspections.manage'), false)
          else true
        end);
    when 'inspection_finding' then
      return query
        select s."id"::text from "better_supabase"."inspection_findings" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'inspections.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'inspections.write'), false)
          else true
        end);
    when 'form' then
      return query
        select s."id"::text from "better_supabase"."forms" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'forms.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'forms.manage'), false)
          else true
        end);
    when 'meeting' then
      return query
        select s."id"::text from "better_supabase"."meetings" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'meetings.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'meetings.write'), false)
          else true
        end);
    when 'meeting_decision' then
      return query
        select s."id"::text from "better_supabase"."meeting_decisions" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'meetings.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'meetings.write'), false)
          else true
        end);
    when 'maintenance_plan' then
      return query
        select s."id"::text from "better_supabase"."maintenance_plans" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'maintenance.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'maintenance.manage'), false)
          else true
        end);
    when 'dam_usage_right' then
      return query
        select s."id"::text from "better_supabase"."dam_usage_rights" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'dam.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'dam.write'), false)
          else true
        end);
    when 'lims_sample' then
      return query
        select s."id"::text from "better_supabase"."lims_samples" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'lims.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'lims.write'), false)
          else true
        end);
    when 'tax_code' then
      return query
        select s."id"::text from "better_supabase"."tax_codes" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[]) and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'tax.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'tax.manage'), false)
          else true
        end);
    when 'production_order' then
      return query
        select s."id"::text from "better_supabase"."production_orders" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'manufacturing.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'manufacturing.write'), false)
          else true
        end);
    when 'work_center' then
      return query
        select s."id"::text from "better_supabase"."work_centers" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[]) and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'manufacturing.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'manufacturing.manage'), false)
          else true
        end);
    when 'bank_account' then
      return query
        select s."id"::text from "better_supabase"."bank_accounts" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[]) and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'banking.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'banking.manage'), false)
          else true
        end);
    when 'care_plan' then
      return query
        select s."id"::text from "better_supabase"."care_plans" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'care_plans.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'care_plans.write'), false)
          else true
        end);
    when 'incident' then
      return query
        select s."id"::text from "better_supabase"."incidents" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'incidents.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'incidents.write'), false)
          else true
        end);
    when 'advisory' then
      return query
        select s."id"::text from "better_supabase"."advisories" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'advisories.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'advisories.write'), false)
          else true
        end);
    when 'advisory_product' then
      return query
        select s."id"::text from "better_supabase"."advisory_products" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[]) and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'advisories.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'advisories.write'), false)
          else true
        end);
    when 'vulnerability' then
      return query
        select s."id"::text from "better_supabase"."vulnerabilities" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'advisories.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'advisories.write'), false)
          else true
        end);
    when 'content_entry' then
      return query
        select s."id"::text from "better_supabase"."content_entries" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'content.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'content.write'), false)
          else true
        end);
    when 'document' then
      return query
        select s."id"::text from "better_supabase"."documents" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'documents.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'documents.write'), false)
          else true
        end);
    when 'customer' then
      return query
        select s."id"::text from "public"."customers" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[]) and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then (coalesce(better_supabase.can('tenant', s."organization_id", 'customers.read'), false) or "better_supabase"."is_subject_member"('customer', s."id"::text))
          when 'write' then (coalesce(better_supabase.can('tenant', s."organization_id", 'customers.write'), false) or "better_supabase"."is_subject_member"('customer', s."id"::text))
          else true
        end);
    when 'drive_node' then
      return query
        select s."id"::text from "better_supabase"."drive_nodes" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[]) and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then ((coalesce(better_supabase.can('tenant', s."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)) or "better_supabase"."is_subject_member"('drive_node', s."id"::text))
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'drive.manage'), false)
          when 'comment' then coalesce("better_supabase"."drive_can_comment"(s."id"), false)
          when 'fields' then coalesce("better_supabase"."drive_node_writable"(s."id"), false)
          else true
        end);
    when 'organization' then
      return query
        select s."id"::text from "public"."organizations" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and true;
    when 'application' then
      return query
        select s."id"::text from "better_supabase"."applications" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'hiring.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'hiring.write'), false)
          else true
        end);
    when 'change_request' then
      return query
        select s."id"::text from "public"."change_requests" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and true;
    when 'project' then
      return query
        select s."id"::text from "public"."projects" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[]) and s."deleted_at" is null
          and true;
    when 'task' then
      return query
        select s."id"::text from "public"."tasks" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and true;
    else
      return;
  end case;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.claim_time_for_invoice (
  tenant    uuid,
  invoice   uuid,
  entry_ids jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_claimed jsonb;
  v_expected integer := jsonb_array_length(claim_time_for_invoice.entry_ids);
begin
  perform pg_advisory_xact_lock(hashtextextended('billable_time:' || claim_time_for_invoice.tenant::text, 0));
  with claimed as (
    insert into "better_supabase"."time_invoice_entries" ("entry_id", "tenant_id", "invoice_id", "rate", "currency", "seconds")
    select u.id, claim_time_for_invoice.tenant, claim_time_for_invoice.invoice, u.rate, u.currency, round(u.seconds)::bigint
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
    where x."tenant_id" = claim_time_for_invoice.tenant
      and x."billable" and x."ended_at" is not null and x."archived_at" is null
      and not exists (select 1 from "better_supabase"."time_invoice_entries" d where d."entry_id" = x."id")
      and (jsonb_build_object('entryIds', claim_time_for_invoice.entry_ids) -> 'subject' is null or (x."subject_type" = jsonb_build_object('entryIds', claim_time_for_invoice.entry_ids) -> 'subject' ->> 'type' and x."subject_id" = jsonb_build_object('entryIds', claim_time_for_invoice.entry_ids) -> 'subject' ->> 'id'))
      and (jsonb_build_object('entryIds', claim_time_for_invoice.entry_ids) ->> 'userId' is null or x."user_id" = (jsonb_build_object('entryIds', claim_time_for_invoice.entry_ids) ->> 'userId')::uuid)
      and (jsonb_build_object('entryIds', claim_time_for_invoice.entry_ids) ->> 'starts' is null or x."started_at" >= (jsonb_build_object('entryIds', claim_time_for_invoice.entry_ids) ->> 'starts')::timestamptz)
      and (jsonb_build_object('entryIds', claim_time_for_invoice.entry_ids) ->> 'ends' is null or x."started_at" < (jsonb_build_object('entryIds', claim_time_for_invoice.entry_ids) ->> 'ends')::timestamptz)
      and (jsonb_build_object('entryIds', claim_time_for_invoice.entry_ids) -> 'entryIds' is null or x."id"::text in (select jsonb_array_elements_text(jsonb_build_object('entryIds', claim_time_for_invoice.entry_ids) -> 'entryIds')))) u
    where u.rate is not null
    returning "entry_id" as entry_id, "seconds" as seconds)
  select coalesce(jsonb_agg(jsonb_build_object('entryId', c.entry_id, 'seconds', c.seconds)), '[]'::jsonb) into v_claimed from claimed c;
  if jsonb_array_length(v_claimed) <> v_expected then
    raise exception 'some time entries were billed in the meantime' using errcode = '55000', hint = 'BILLABLE_TIME_STALE';
  end if;
  return v_claimed;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.collect_payroll_lines (
  run_id uuid
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_run "better_supabase"."payroll_runs"%rowtype;
  v_added integer;
  v_count integer := 0;
begin
  select * into v_run from "better_supabase"."payroll_runs" x where x."id" = collect_payroll_lines.run_id;
  delete from "better_supabase"."payroll_lines" where "run_id" = v_run."id";
  insert into "better_supabase"."payroll_lines" ("tenant_id", "run_id", "user_id", "employee_id", "kind", "unit", "quantity", "source_count")
  select v_run."tenant_id", v_run."id", x."user_id", null::uuid,
    'worked', 'hours', round(sum(extract(epoch from x."ended_at" - x."started_at"))::numeric / 3600, 2), count(*)
  from "better_supabase"."time_entries" x
  where x."tenant_id" = v_run."tenant_id"
    and x."ended_at" is not null and x."archived_at" is null
    and x."user_id" is not null
    and "better_supabase"."time_week_approved"(x."tenant_id", x."user_id", x."started_at")
    and (x."started_at" at time zone 'UTC')::date between v_run."period_from" and v_run."period_to"
  group by x."user_id"
  having sum(extract(epoch from x."ended_at" - x."started_at")) > 0;
  get diagnostics v_added = row_count;
  v_count := v_count + v_added;
  insert into "better_supabase"."payroll_lines" ("tenant_id", "run_id", "user_id", "employee_id", "kind", "code", "paid", "unit", "quantity", "source_count")
  select v_run."tenant_id", v_run."id", q."user_id", null::uuid, 'leave', t."key", t."paid",
    case when t."unit" = 'hours' then 'hours' else 'days' end, sum(q."amount"), count(*)
  from "better_supabase"."leave_requests" q
  join "better_supabase"."leave_types" t on t."id" = q."type_id"
  where q."tenant_id" = v_run."tenant_id"
    and q."approved_at" is not null and q."cancelled_at" is null
    and q."starts_on" between v_run."period_from" and v_run."period_to"
  group by q."user_id", t."key", t."paid", t."unit";
  get diagnostics v_added = row_count;
  v_count := v_count + v_added;
  update "better_supabase"."payroll_lines" x
  set "employee_id" = e."id", "employee_name" = e."name"
  from "better_supabase"."employees" e
  where x."run_id" = v_run."id"
    and e."tenant_id" = v_run."tenant_id"
    and (e."id" = x."employee_id" or (x."employee_id" is null and e."user_id" = x."user_id"));
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.complete_activity (
  activity uuid,
  done     boolean,
  outcome  text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid := complete_activity.activity;
  v_tenant uuid;
  v_type text;
  v_subjects jsonb := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."activity_subjects" sx where sx."activity_id" = complete_activity.activity), '[]'::jsonb);
  v_first jsonb := v_subjects -> 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if exists (select 1 from "better_supabase"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the activity is locked: add an addendum with amend_activity instead' using errcode = '55000', hint = 'ACTIVITY_LOCKED';
  end if;
  if exists (select 1 from "better_supabase"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and x."archived_at" is not null) then
    raise exception 'the activity is archived: restore it first' using errcode = '55000', hint = 'ACTIVITY_ARCHIVED';
  end if;
  update "better_supabase"."activities" x set
    "done_at" = case when complete_activity.done then coalesce(x."done_at", now()) end,
    "outcome" = coalesce(complete_activity.outcome, x."outcome"),
    "updated_at" = now()
  where x."id" = v_id and ((auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and x."archived_at" is null)
  returning x."tenant_id", x."type" into v_tenant, v_type;
  if v_tenant is null then
    raise exception 'no such activity you can edit' using errcode = 'P0002', hint = 'ACTIVITY_NOT_FOUND';
  end if;
  if complete_activity.done then
    perform "better_supabase".emit_event('activity.completed', jsonb_build_object('organizationId', v_tenant, 'activityId', v_id, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects), 'activities/' || v_id::text, (v_tenant::text)::text, null, 'better-supabase/activities');
  end if;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."activity_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."activities" x where x."id" = v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.evaluate_segment (
  segment uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."segments";
  v_fields jsonb;
  v_now timestamptz := now();
  v_ids text[];
  v_entered text[];
  v_left text[];
  v_id text;
begin
  select * into v_row from "better_supabase"."segments" x where x."id" = evaluate_segment.segment for update;
  if v_row."id" is null then
    return null;
  end if;
  v_fields := "better_supabase"."rule_field_map"(v_row."subject_type");
  if v_row."subject_type" = 'message' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."messages" s
      where s."tenant_id" = v_row."tenant_id" and s."archived_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'conversation' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."conversations" s
      where s."tenant_id" = v_row."tenant_id" and s."archived_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'channel' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."channels" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'company' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."companies" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'person' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."people" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'deal' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."deals" s
      where s."tenant_id" = v_row."tenant_id" and s."archived_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'course' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."courses" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'post' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."posts" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'activity' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."activities" s
      where s."tenant_id" = v_row."tenant_id" and s."archived_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'quote' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."quotes" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'work_item' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."work_items" s
      where s."tenant_id" = v_row."tenant_id" and s."archived_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'employee' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."employees" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'ledger_account' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."ledger_accounts" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'invoice' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."invoices" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'product' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."products" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'product_variant' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."product_variants" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'rfq' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."rfqs" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'till' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."tills" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'order' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."orders" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'calendar_event' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."calendar_events" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'booking' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."bookings" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'asset' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."assets" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'asset_location' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."asset_locations" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'lease' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."leases" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'expense_report' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."expense_reports" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'expense_line' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."expense_lines" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'donation_fund' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."donation_funds" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'warranty_claim' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."warranty_claims" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'work_order' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."work_orders" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'shipment' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."shipments" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'contract' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."contracts" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'control' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."controls" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'compliance_policy' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."compliance_policies" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'qualification_type' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."qualification_types" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'risk' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."risks" s
      where s."tenant_id" = v_row."tenant_id" and s."archived_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'case' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."cases" s
      where s."tenant_id" = v_row."tenant_id" and s."archived_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'inspection' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."inspections" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'inspection_program' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."inspection_programs" s
      where s."tenant_id" = v_row."tenant_id" and s."archived_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'inspection_finding' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."inspection_findings" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'form' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."forms" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'meeting' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."meetings" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'meeting_decision' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."meeting_decisions" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'maintenance_plan' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."maintenance_plans" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'dam_usage_right' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."dam_usage_rights" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'lims_sample' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."lims_samples" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'tax_code' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."tax_codes" s
      where s."tenant_id" = v_row."tenant_id" and s."archived_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'production_order' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."production_orders" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'work_center' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."work_centers" s
      where s."tenant_id" = v_row."tenant_id" and s."archived_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'bank_account' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."bank_accounts" s
      where s."tenant_id" = v_row."tenant_id" and s."archived_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'care_plan' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."care_plans" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'incident' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."incidents" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'advisory' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."advisories" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'advisory_product' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."advisory_products" s
      where s."tenant_id" = v_row."tenant_id" and s."archived_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'vulnerability' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."vulnerabilities" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'content_entry' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."content_entries" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'document' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."documents" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'customer' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "public"."customers" s
      where s."organization_id" = v_row."tenant_id" and s."archived_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'drive_node' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."drive_nodes" s
      where s."tenant_id" = v_row."tenant_id" and s."archived_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'organization' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "public"."organizations" s
      where s."id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'application' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."applications" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'change_request' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "public"."change_requests" s
      where s."organization_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'project' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "public"."projects" s
      where s."organization_id" = v_row."tenant_id" and s."deleted_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'task' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "public"."tasks" s
      where s."organization_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  else
    raise exception 'The segment''s subject type is not registered in config.recordTypes' using errcode = '22023', hint = 'SEGMENT_SUBJECT_UNKNOWN';
  end if;
  if cardinality(v_ids) > 10000 then
    raise exception 'A segment holds at most 10000 records; narrow its conditions' using errcode = '54000', hint = 'SEGMENT_TOO_LARGE';
  end if;
  with gone as (
    delete from "better_supabase"."segment_members" y
    where y."segment_id" = v_row."id" and not (y."subject_id" = any (v_ids))
    returning y."subject_id" as id
  ), added as (
    insert into "better_supabase"."segment_members" ("segment_id", "tenant_id", "subject_id", "entered_at")
    select v_row."id", v_row."tenant_id", z, v_now from unnest(v_ids) z
    on conflict do nothing
    returning "subject_id" as id
  )
  select coalesce((select array_agg(g.id order by g.id) from gone g), '{}'),
    coalesce((select array_agg(a.id order by a.id) from added a), '{}')
  into v_left, v_entered;
  foreach v_id in array v_entered loop
    perform "better_supabase".emit_event('segment.entered', jsonb_build_object('organizationId', v_row."tenant_id", 'segmentId', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_id), 'segments/' || v_row."id"::text, (v_row."tenant_id"::text)::text, 'segment.entered:' || v_row."id"::text || ':' || v_id || ':' || extract(epoch from v_now)::text, 'better-supabase/segments');
  end loop;
  foreach v_id in array v_left loop
    perform "better_supabase".emit_event('segment.left', jsonb_build_object('organizationId', v_row."tenant_id", 'segmentId', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_id), 'segments/' || v_row."id"::text, (v_row."tenant_id"::text)::text, 'segment.left:' || v_row."id"::text || ':' || v_id || ':' || extract(epoch from v_now)::text, 'better-supabase/segments');
  end loop;
  update "better_supabase"."segments" x set "member_count" = cardinality(v_ids), "refreshed_at" = v_now
  where x."id" = v_row."id";
  return jsonb_build_object('entered', cardinality(v_entered), 'left', cardinality(v_left), 'memberCount', cardinality(v_ids));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_timesheet (
  tenant  uuid,
  week    date,
  user_id uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_user uuid := coalesce(get_timesheet.user_id, auth.uid());
  v_week date := date_trunc('week', get_timesheet.week)::date;
  v_sheet "better_supabase"."timesheets"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_json jsonb;
  v_entries jsonb;
  v_totals jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(v_user = auth.uid(), false) and coalesce(better_supabase.can('tenant', get_timesheet.tenant, 'time_entries.track'), false)) or coalesce(better_supabase.can('tenant', get_timesheet.tenant, 'time_entries.read'), false)) then
    raise exception 'not allowed to read this timesheet' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  select * into v_sheet from "better_supabase"."timesheets" s
    where s."tenant_id" = get_timesheet.tenant and s."user_id" = v_user and s."week" = v_week;
  if found then
    select * into v_approval from "better_supabase"."approval_requests" x where x."id" = v_sheet."approval_id";
    v_json := jsonb_build_object('id', v_sheet."id", 'organizationId', v_sheet."tenant_id", 'userId', v_sheet."user_id", 'week', v_sheet."week", 'status', case when v_sheet."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" = 'rejected' then 'rejected' else 'open' end, 'approvalId', v_sheet."approval_id", 'note', v_sheet."note", 'submittedAt', v_sheet."submitted_at", 'approvedAt', v_sheet."approved_at", 'createdAt', v_sheet."created_at");
  else
    v_json := jsonb_build_object('id', null, 'organizationId', get_timesheet.tenant, 'userId', v_user, 'week', v_week, 'status', 'open');
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'startedAt', x."started_at", 'endedAt', x."ended_at", 'seconds', case when x."ended_at" is null then null else extract(epoch from x."ended_at" - x."started_at")::bigint end, 'billable', x."billable", 'rate', x."rate"::text, 'rateCurrency', x."rate_currency", 'note', x."note", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") order by x."started_at"), '[]'::jsonb),
    jsonb_build_object(
      'seconds', coalesce(sum(extract(epoch from coalesce(x."ended_at", now()) - x."started_at")), 0)::bigint,
      'billableSeconds', coalesce(sum(extract(epoch from coalesce(x."ended_at", now()) - x."started_at")) filter (where x."billable"), 0)::bigint,
      -- Billable hours times the rate, per currency, rounded to minor units.
      'amounts', (
        select coalesce(jsonb_agg(jsonb_build_object('amount', q.amount::text, 'currency', q.currency) order by q.currency), '[]'::jsonb)
        from (
          select y."rate_currency" as currency,
            round(sum(extract(epoch from coalesce(y."ended_at", now()) - y."started_at") * y."rate" / 3600))::bigint as amount
          from "better_supabase"."time_entries" y
          where y."tenant_id" = get_timesheet.tenant and y."user_id" = v_user
            and "better_supabase"."time_week"(y."started_at") = v_week
            and y."billable" and y."rate" is not null and y."archived_at" is null
          group by y."rate_currency"
        ) q
      )
    )
    into v_entries, v_totals
  from "better_supabase"."time_entries" x
  where x."tenant_id" = get_timesheet.tenant and x."user_id" = v_user
    and "better_supabase"."time_week"(x."started_at") = v_week and x."archived_at" is null;
  return v_json || jsonb_build_object('entries', v_entries, 'totals', v_totals);
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
      and x."billable" and x."ended_at" is not null and x."archived_at" is null
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
      and x."billable" and x."ended_at" is not null and x."archived_at" is null
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
      and x."billable" and x."ended_at" is not null and x."archived_at" is null
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

CREATE OR REPLACE FUNCTION better_supabase.list_time_entries (
  tenant       uuid,
  user_id      uuid                     DEFAULT NULL::uuid,
  starts       timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  ends         timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  subject_type text                     DEFAULT NULL::text,
  subject_id   text                     DEFAULT NULL::text,
  everyone     boolean                  DEFAULT false,
  page_size    integer                  DEFAULT 200,
  archived     boolean                  DEFAULT false
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_user uuid := coalesce(list_time_entries.user_id, auth.uid());
  v_rows jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or ((coalesce(v_user = auth.uid(), false) and not list_time_entries.everyone) and coalesce(better_supabase.can('tenant', list_time_entries.tenant, 'time_entries.track'), false)) or coalesce(better_supabase.can('tenant', list_time_entries.tenant, 'time_entries.read'), false)) then
    raise exception 'not allowed to read these entries' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'userId', q."user_id", 'subjectType', q."subject_type", 'subjectId', q."subject_id", 'startedAt', q."started_at", 'endedAt', q."ended_at", 'seconds', case when q."ended_at" is null then null else extract(epoch from q."ended_at" - q."started_at")::bigint end, 'billable', q."billable", 'rate', q."rate"::text, 'rateCurrency', q."rate_currency", 'note', q."note", 'createdAt', q."created_at", 'updatedAt', q."updated_at", 'archivedAt', q."archived_at") order by q."started_at" desc), '[]'::jsonb) into v_rows
  from (
    select * from "better_supabase"."time_entries" x
    where x."tenant_id" = list_time_entries.tenant
      and (list_time_entries.everyone or x."user_id" = v_user)
      and (list_time_entries.starts is null or coalesce(x."ended_at", 'infinity'::timestamptz) > list_time_entries.starts)
      and (list_time_entries.ends is null or x."started_at" < list_time_entries.ends)
      and (list_time_entries.subject_type is null or x."subject_type" = list_time_entries.subject_type)
      and (list_time_entries.subject_id is null or x."subject_id" = list_time_entries.subject_id)
      and ((x."archived_at" is not null) = coalesce(list_time_entries.archived, false))
    order by x."started_at" desc
    limit least(greatest(coalesce(list_time_entries.page_size, 200), 1), 1000)
  ) q;
  return v_rows;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_trash (
  tenant       uuid,
  subject_type text                     DEFAULT NULL::text,
  page_size    integer                  DEFAULT 50,
  before       timestamp with time zone DEFAULT NULL::timestamp WITH time zone
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_trash.tenant, 'trash.read'), false)) then
    raise exception 'not allowed to read this organization''s trash' using errcode = '42501', hint = 'TRASH_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', t."id", 'subjectType', t."subject_type", 'subjectId', t."subject_id", 'title', t."title", 'batchId', t."batch_id", 'count', t.n, 'trashedBy', t."trashed_by", 'trashedAt', t."trashed_at", 'purgeAfter', t."purge_at") order by t."trashed_at" desc, t."id"), '[]'::jsonb)
    into v_rows
  from (
    select x.*, (select count(*) from "better_supabase"."trash_items" b where b."batch_id" = x."batch_id")::integer as n
    from "better_supabase"."trash_items" x
    where x."tenant_id" = list_trash.tenant
      and x."depth" = 0
      and (list_trash.subject_type is null or x."subject_type" = list_trash.subject_type)
      and (list_trash.before is null or x."trashed_at" < list_trash.before)
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case x."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.read'), false)
    when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.read'), false)
    when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'risks.read'), false)
    when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'cases.read'), false)
    when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'inspections.read'), false)
    when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tax.read'), false)
    when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'manufacturing.read'), false)
    when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'banking.read'), false)
    when 'advisory_product' then exists (select 1 from "better_supabase"."advisory_products" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'advisories.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id" and (coalesce(better_supabase.can('tenant', x."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    else false
  end)
    order by x."trashed_at" desc, x."id"
    limit least(greatest(coalesce(list_trash.page_size, 50), 1), 200)
  ) t;
  return v_rows;
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
    raise exception 'not allowed to log activities' using errcode = '42501', hint = 'ACTIVITY_FORBIDDEN';
  end if;
  if v_type is null or not (v_type = any ('{call,email,meeting,note,task}'::text[])) then
    raise exception 'unknown activity type' using errcode = '22023', hint = 'ACTIVITY_TYPE_INVALID';
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
  if exists (select 1 from "better_supabase"."activities" x where x."tenant_id" = v_tenant and x."external_ref" = log_activity.attrs ->> 'externalRef' and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the activity is locked: add an addendum with amend_activity instead' using errcode = '55000', hint = 'ACTIVITY_LOCKED';
  end if;
  if exists (select 1 from "better_supabase"."activities" x where x."tenant_id" = v_tenant and x."external_ref" = log_activity.attrs ->> 'externalRef' and x."archived_at" is not null) then
    raise exception 'the activity is archived: restore it first' using errcode = '55000', hint = 'ACTIVITY_ARCHIVED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_activity_log"(uuid, jsonb, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb, $3::jsonb)', v_hook::oid::regproc)
        using log_activity.tenant, log_activity.attrs, log_activity.subjects;
    end if;
  end;
  insert into "better_supabase"."activities" ("tenant_id", "type", "title", "body", "outcome", "owner_id", "due_at", "done_at", "duration_seconds", "external_ref", "created_by", "audience", "restricted_roles", "category", "locked_at", "goal_id")
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
      when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'rfq' then exists (select 1 from "better_supabase"."rfqs" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'till' then exists (select 1 from "better_supabase"."tills" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'warranty_claim' then exists (select 1 from "better_supabase"."warranty_claims" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'meeting' then exists (select 1 from "better_supabase"."meetings" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'meeting_decision' then exists (select 1 from "better_supabase"."meeting_decisions" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'maintenance_plan' then exists (select 1 from "better_supabase"."maintenance_plans" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'dam_usage_right' then exists (select 1 from "better_supabase"."dam_usage_rights" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'lims_sample' then exists (select 1 from "better_supabase"."lims_samples" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'advisory' then exists (select 1 from "better_supabase"."advisories" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'advisory_product' then exists (select 1 from "better_supabase"."advisory_products" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'vulnerability' then exists (select 1 from "better_supabase"."vulnerabilities" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'organization' then exists (select 1 from "public"."organizations" s where s."id" = ((v_item ->> 'id'))::uuid and s."id"::text = v_tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      else false
    end and "better_supabase"."can_subject"((v_item ->> 'type'), (v_item ->> 'id'), 'read')) then
      raise exception 'a subject is unknown or not readable in this organization' using errcode = '42501', hint = 'ACTIVITY_SUBJECT_FORBIDDEN';
    end if;
  end loop;
  delete from "better_supabase"."activity_subjects" x where x."activity_id" = v_id;
  insert into "better_supabase"."activity_subjects" ("tenant_id", "activity_id", "subject_type", "subject_id", "position")
  select v_tenant, v_id, s.value ->> 'type', s.value ->> 'id', s.ordinality::integer
  from jsonb_array_elements(coalesce(log_activity.subjects, '[]')) with ordinality s
  on conflict do nothing;
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."activity_subjects" sx where sx."activity_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  perform "better_supabase".emit_event('activity.logged', jsonb_build_object('organizationId', v_tenant, 'activityId', v_id, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects), 'activities/' || v_id::text, (v_tenant::text)::text, null, 'better-supabase/activities');
  if v_owner is not null and v_owner is distinct from auth.uid() and v_owner is distinct from v_previous_owner then
    if better_supabase.import_run() is null then
      v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'activity.assigned',
      'tenant', v_tenant,
      'actor', auth.uid(),
      'subject_type', v_first ->> 'type',
      'subject_id', v_first ->> 'id',
      'summary', v_title,
      'recipients', jsonb_build_array(v_owner),
      'watchers', false,
      'key', 'activity.assigned:' || v_id::text || ':' || v_owner::text,
      'data', jsonb_build_object('activityId', v_id)
    ));
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_activity_log"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."activity_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."activities" x where x."id" = v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.log_time (
  tenant        uuid,
  started_at    timestamp with time zone,
  ended_at      timestamp with time zone,
  subject_type  text                     DEFAULT NULL::text,
  subject_id    text                     DEFAULT NULL::text,
  billable      boolean                  DEFAULT false,
  rate          bigint                   DEFAULT NULL::bigint,
  rate_currency text                     DEFAULT NULL::text,
  note          text                     DEFAULT NULL::text,
  user_id       uuid                     DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_user uuid := coalesce(log_time.user_id, auth.uid());
  v_row "better_supabase"."time_entries"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_user is null then
    raise exception 'sign in to track time' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if v_user = v_me then
    if not coalesce(better_supabase.can('tenant', log_time.tenant, 'time_entries.track'), false) then
      raise exception 'not allowed to track time here' using errcode = '42501', hint = 'TIME_FORBIDDEN';
    end if;
  elsif not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', log_time.tenant, 'time_entries.manage'), false)) then
    raise exception 'not allowed to log time for another member' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  elsif not exists (select 1 from "public"."memberships" m where m."organization_id" = log_time.tenant and m."user_id" = v_user) then
    raise exception 'that user isn''t a member of this organization' using errcode = '22023', hint = 'TIME_USER_INVALID';
  end if;
  if log_time.started_at is null or log_time.ended_at is null or log_time.ended_at <= log_time.started_at then
    raise exception 'ended_at must be after started_at' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
  end if;
  if (log_time.subject_type is null) <> (log_time.subject_id is null) then
    raise exception 'name both subject_type and subject_id, or neither' using errcode = '22023', hint = 'TIME_SUBJECT_INVALID';
  end if;
  if log_time.subject_type is not null and log_time.subject_type <> all (array['company', 'project']::text[]) then
    raise exception 'time is tracked on company, project records' using errcode = '22023', hint = 'TIME_SUBJECT_INVALID';
  end if;
  if log_time.subject_type is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case log_time.subject_type
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'contacts.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'contacts.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'posts.read'), false)
    when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'activities.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'tasks.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'ledger.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'invoices.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'catalog.read'), false)
    when 'rfq' then exists (select 1 from "better_supabase"."rfqs" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'rfqs.read'), false)
    when 'till' then exists (select 1 from "better_supabase"."tills" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'tills.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'donations.read'), false)
    when 'warranty_claim' then exists (select 1 from "better_supabase"."warranty_claims" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'warranty.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'compliance.read'), false)
    when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'compliance.read'), false)
    when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'qualifications.read'), false)
    when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'risks.read'), false)
    when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'cases.read'), false)
    when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'inspections.read'), false)
    when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'inspections.read'), false)
    when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'inspections.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'forms.read'), false)
    when 'meeting' then exists (select 1 from "better_supabase"."meetings" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'meetings.read'), false)
    when 'meeting_decision' then exists (select 1 from "better_supabase"."meeting_decisions" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'meetings.read'), false)
    when 'maintenance_plan' then exists (select 1 from "better_supabase"."maintenance_plans" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'maintenance.read'), false)
    when 'dam_usage_right' then exists (select 1 from "better_supabase"."dam_usage_rights" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'dam.read'), false)
    when 'lims_sample' then exists (select 1 from "better_supabase"."lims_samples" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'lims.read'), false)
    when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'tax.read'), false)
    when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'manufacturing.read'), false)
    when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'manufacturing.read'), false)
    when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'banking.read'), false)
    when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'care_plans.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'incidents.read'), false)
    when 'advisory' then exists (select 1 from "better_supabase"."advisories" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'advisories.read'), false)
    when 'advisory_product' then exists (select 1 from "better_supabase"."advisory_products" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'advisories.read'), false)
    when 'vulnerability' then exists (select 1 from "better_supabase"."vulnerabilities" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'advisories.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'content.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (log_time.subject_id)::uuid and s."organization_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant and (coalesce(better_supabase.can('tenant', log_time.tenant, 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'organization' then exists (select 1 from "public"."organizations" s where s."id" = (log_time.subject_id)::uuid and s."id" = log_time.tenant)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (log_time.subject_id)::uuid and s."organization_id" = log_time.tenant)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (log_time.subject_id)::uuid and s."organization_id" = log_time.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (log_time.subject_id)::uuid and s."organization_id" = log_time.tenant)
    else false
  end) then
    raise exception 'not allowed to track time on this record' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if log_time.rate is not null and log_time.rate_currency is null then
    raise exception 'a rate needs rate_currency' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  if log_time.rate_currency !~ '^[A-Z]{3}$' then
    raise exception 'rate_currency must be a three-letter currency code' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('time_entry:' || log_time.tenant::text || ':' || v_user::text, 0));
  v_row."id" := gen_random_uuid();
  v_row."tenant_id" := log_time.tenant;
  v_row."user_id" := v_user;
  v_row."subject_type" := log_time.subject_type;
  v_row."subject_id" := log_time.subject_id;
  v_row."started_at" := log_time.started_at;
  v_row."ended_at" := log_time.ended_at;
  v_row."billable" := coalesce(log_time.billable, false);
  v_row."rate" := log_time.rate;
  v_row."rate_currency" := log_time.rate_currency;
  v_row."note" := log_time.note;
  if exists (
    select 1 from "better_supabase"."time_entries" x
    where x."tenant_id" = v_row."tenant_id" and x."user_id" = v_row."user_id" and x."id" <> v_row."id"
      and x."archived_at" is null
      and tstzrange(x."started_at", coalesce(x."ended_at", 'infinity'::timestamptz)) && tstzrange(v_row."started_at", coalesce(v_row."ended_at", 'infinity'::timestamptz))
  ) then
    raise exception 'this time overlaps another entry' using errcode = '23P01', hint = 'TIME_ENTRY_OVERLAP';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_time_entry_save"(uuid, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::uuid)', v_hook::oid::regproc)
        using v_row."id", v_row."tenant_id", v_row."user_id";
    end if;
  end;
  insert into "better_supabase"."time_entries" ("id", "tenant_id", "user_id", "subject_type", "subject_id", "started_at", "ended_at", "billable", "rate", "rate_currency", "note")
  values (v_row."id", v_row."tenant_id", v_row."user_id", v_row."subject_type", v_row."subject_id", v_row."started_at", v_row."ended_at", v_row."billable", v_row."rate", v_row."rate_currency", v_row."note")
  returning * into v_row;
  perform "better_supabase".emit_event('time_entry.recorded', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'id', v_row."id", 'userId', v_row."user_id", 'startedAt', v_row."started_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency"), 'time-entries/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/time-entries');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_time_entry_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.mark_activity_error (
  activity uuid,
  reason   text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid := mark_activity_error.activity;
  v_reason text := nullif(trim(mark_activity_error.reason), '');
  v_tenant uuid;
  v_type text;
  v_subjects jsonb := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."activity_subjects" sx where sx."activity_id" = mark_activity_error.activity), '[]'::jsonb);
  v_first jsonb := v_subjects -> 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_reason is null then
    raise exception 'say why the activity is in error' using errcode = '23502', hint = 'ACTIVITY_REASON_REQUIRED';
  end if;
  if exists (select 1 from "better_supabase"."activities" x where x."id" = v_id and ((auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and x."archived_at" is null) and x."marked_error_at" is not null) then
    raise exception 'the activity is already marked in error' using errcode = '55000', hint = 'ACTIVITY_ALREADY_MARKED_ERROR';
  end if;
  update "better_supabase"."activities" x set
    "marked_error_at" = now(),
    "marked_error_by" = auth.uid(),
    "marked_error_reason" = v_reason,
    "locked_at" = least(coalesce(x."locked_at", now()), now())
  where x."id" = v_id and ((auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and x."archived_at" is null)
  returning x."tenant_id", x."type"::text into v_tenant, v_type;
  if v_tenant is null then
    raise exception 'no such activity you can edit' using errcode = 'P0002', hint = 'ACTIVITY_NOT_FOUND';
  end if;
  perform "better_supabase".emit_event('activity.error_marked', jsonb_build_object('organizationId', v_tenant, 'activityId', v_id, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects, 'reason', v_reason), 'activities/' || v_id::text, (v_tenant::text)::text, null, 'better-supabase/activities');
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."activity_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."activities" x where x."id" = v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.next_activity (
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."activity_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now())
  from "better_supabase"."activities" x
  join "better_supabase"."activity_subjects" k on k."activity_id" = x."id"
  where k."subject_type" = next_activity.subject_type and k."subject_id" = next_activity.subject_id
    and x."done_at" is null and x."due_at" is not null and x."archived_at" is null
  order by x."due_at", x."id"
  limit 1
$function$;

CREATE OR REPLACE FUNCTION better_supabase.open_activities (
  tenant     uuid,
  owner      uuid,
  due_before timestamp with time zone,
  page_size  integer
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(p.value order by p.due nulls last, p.id), '[]'::jsonb)
  from (
    select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."activity_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) as value, x."due_at" as due, x."id" as id
    from "better_supabase"."activities" x
    where x."tenant_id" = open_activities.tenant
      and x."owner_id" = coalesce(open_activities.owner, auth.uid())
      and x."done_at" is null and x."archived_at" is null
      and (open_activities.due_before is null or x."due_at" < open_activities.due_before)
    order by x."due_at" nulls last, x."id"
    limit least(greatest(coalesce(open_activities.page_size, 50), 1), 200)
  ) p
$function$;

CREATE OR REPLACE FUNCTION better_supabase.pending_activity_recordings (
  batch integer
)
  RETURNS uuid[]
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(array_agg(p.id order by p.at), '{}')
  from (
    select rx."id" as id, rx."created_at" as at
    from "better_supabase"."activity_recordings" rx
    where rx."status" = 'pending'
      and not exists (select 1 from "better_supabase"."activities" ax where ax."id" = rx."activity_id" and ax."archived_at" is not null)
    order by rx."created_at"
    limit least(greatest(coalesce(pending_activity_recordings.batch, 20), 1), 200)
  ) p
$function$;

CREATE OR REPLACE FUNCTION better_supabase.project_costs (
  project_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_project "better_supabase"."work_projects"%rowtype;
  v_result jsonb;
begin
  select * into v_project from "better_supabase"."work_projects" x where x."id" = project_costs.project_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_project."tenant_id", 'billable_time.read'), false)) then
    raise exception 'project not found' using errcode = 'P0002', hint = 'TASK_PROJECT_NOT_FOUND';
  end if;
  with spent as (
    select extract(epoch from x."ended_at" - x."started_at") as seconds, card.cost, card.currency,
      d."rate" as billed_rate, d."currency"::text as billed_currency, d."seconds" as billed_seconds
    from "better_supabase"."time_entries" x
    left join lateral (
      select c."cost_amount" as cost, c."currency"::text as currency
      from "better_supabase"."time_rates" c
      where c."tenant_id" = x."tenant_id"
        and (c."user_id" is null or c."user_id" = x."user_id")
        and (c."subject_type" is null or (c."subject_type" = x."subject_type" and c."subject_id" = x."subject_id"))
        and c."effective_from" <= (x."started_at" at time zone 'UTC')::date
      order by (c."subject_type" is not null) desc, (c."user_id" is not null) desc, c."effective_from" desc
      limit 1
    ) card on true
    left join "better_supabase"."time_invoice_entries" d on d."entry_id" = x."id"
      and not exists (
        select 1 from "better_supabase"."accounting_entries" n
        join "better_supabase"."accounting_entry_lines" l on l."entry_id" = n."id"
        join "better_supabase"."accounting_accounts" a on a."id" = l."account_id"
        where n."tenant_id" = v_project."tenant_id"
          and n."source_type" = 'invoice' and n."source_id" = d."invoice_id"::text
          and n."status" in ('posted', 'reversed')
          and a."type" = 'income'
          and l."dimensions" ->> 'project' = v_project."id"::text
      )
    where x."tenant_id" = v_project."tenant_id"
      and x."ended_at" is not null and x."archived_at" is null
      and ((x."subject_type" = 'project' and x."subject_id" = v_project."id"::text) or (x."subject_type" = 'work_item' and x."subject_id" in (
        select y."id"::text from "better_supabase"."work_items" y where y."project_id" = v_project."id"
      )))
  ),
  totals as (
    select u.currency, sum(u.time_cost)::bigint as time_cost, sum(u.billed)::bigint as billed,
      sum(u.expenses)::bigint as expenses, sum(u.income)::bigint as income
    from (
      select s.currency, round(s.seconds / 3600.0 * s.cost)::bigint as time_cost, 0::bigint as billed, 0::bigint as expenses, 0::bigint as income
      from spent s where s.cost is not null
      union all
      select s.billed_currency, 0, round(s.billed_seconds / 3600.0 * s.billed_rate)::bigint, 0, 0
      from spent s where s.billed_rate is not null
      union all
      select q.currency, 0, 0, q.expenses, q.income from (select l."currency"::text as currency,
        coalesce(sum(l."debit" - l."credit") filter (where a."type" = 'expense'), 0)::bigint as expenses,
        coalesce(sum(l."credit" - l."debit") filter (where a."type" = 'income'), 0)::bigint as income
      from "better_supabase"."accounting_entry_lines" l
      join "better_supabase"."accounting_entries" n on n."id" = l."entry_id"
      join "better_supabase"."accounting_accounts" a on a."id" = l."account_id"
      where l."tenant_id" = v_project."tenant_id"
        and n."status" in ('posted', 'reversed')
        and l."dimensions" ->> 'project' = v_project."id"::text
      group by l."currency") q
    ) u
    group by u.currency
  )
  select jsonb_build_object(
    'projectId', v_project."id",
    'organizationId', v_project."tenant_id",
    'hours', (select round(coalesce(sum(s.seconds), 0) / 3600.0, 2) from spent s),
    'uncostedHours', (select round(coalesce(sum(s.seconds) filter (where s.cost is null), 0) / 3600.0, 2) from spent s),
    'budgetAmount', v_project."budget_amount"::text,
    'budgetCurrency', v_project."budget_currency",
    'budgetHours', v_project."budget_hours",
    'totals', (
      select coalesce(jsonb_agg(jsonb_build_object(
          'currency', t.currency,
          'timeCost', t.time_cost::text,
          'billed', t.billed::text,
          'expenses', t.expenses::text,
          'income', t.income::text,
          'margin', (t.billed + t.income - t.time_cost - t.expenses)::text
        ) order by t.currency), '[]'::jsonb)
      from totals t))
  into v_result;
  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_activity (
  activity uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid := purge_activity.activity;
  v_tenant uuid;
  v_type text;
  v_subjects jsonb := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."activity_subjects" sx where sx."activity_id" = purge_activity.activity), '[]'::jsonb);
  v_first jsonb := v_subjects -> 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if exists (select 1 from "better_supabase"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the activity is locked: add an addendum with amend_activity instead' using errcode = '55000', hint = 'ACTIVITY_LOCKED';
  end if;
  delete from "better_supabase"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false))
  returning x."tenant_id", x."type" into v_tenant, v_type;
  if v_tenant is null then
    return false;
  end if;
  perform "better_supabase".emit_event('activity.purged', jsonb_build_object('organizationId', v_tenant, 'activityId', v_id, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects), 'activities/' || v_id::text, (v_tenant::text)::text, null, 'better-supabase/activities');
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_time_entry (
  entry_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."time_entries"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."time_entries" x where x."id" = purge_time_entry.entry_id for update;
  if not found then
    raise exception 'time entry not found' using errcode = 'P0002', hint = 'TIME_ENTRY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(v_row."user_id" = auth.uid(), false) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'time_entries.track'), false)) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'time_entries.manage'), false)) then
    raise exception 'not allowed to purge this entry' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  delete from "better_supabase"."time_entries" x where x."id" = v_row."id";
  perform "better_supabase".emit_event('time_entry.purged', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'id', v_row."id", 'userId', v_row."user_id", 'startedAt', v_row."started_at"), 'time-entries/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/time-entries');
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.reaction_subject_visible (
  subject_type text,
  subject_id   text,
  tenant       uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
begin
  return case reaction_subject_visible.subject_type
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant and s."archived_at" is null) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant and s."archived_at" is null) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'contacts.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'contacts.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant and s."archived_at" is null) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'posts.read'), false)
    when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant and s."archived_at" is null) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'activities.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant and s."archived_at" is null) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'tasks.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'ledger.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'invoices.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'catalog.read'), false)
    when 'rfq' then exists (select 1 from "better_supabase"."rfqs" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'rfqs.read'), false)
    when 'till' then exists (select 1 from "better_supabase"."tills" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'tills.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'donations.read'), false)
    when 'warranty_claim' then exists (select 1 from "better_supabase"."warranty_claims" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'warranty.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'compliance.read'), false)
    when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'compliance.read'), false)
    when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'qualifications.read'), false)
    when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant and s."archived_at" is null) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'risks.read'), false)
    when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant and s."archived_at" is null) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'cases.read'), false)
    when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'inspections.read'), false)
    when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant and s."archived_at" is null) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'inspections.read'), false)
    when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'inspections.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'forms.read'), false)
    when 'meeting' then exists (select 1 from "better_supabase"."meetings" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'meetings.read'), false)
    when 'meeting_decision' then exists (select 1 from "better_supabase"."meeting_decisions" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'meetings.read'), false)
    when 'maintenance_plan' then exists (select 1 from "better_supabase"."maintenance_plans" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'maintenance.read'), false)
    when 'dam_usage_right' then exists (select 1 from "better_supabase"."dam_usage_rights" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'dam.read'), false)
    when 'lims_sample' then exists (select 1 from "better_supabase"."lims_samples" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'lims.read'), false)
    when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant and s."archived_at" is null) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'tax.read'), false)
    when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'manufacturing.read'), false)
    when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant and s."archived_at" is null) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'manufacturing.read'), false)
    when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant and s."archived_at" is null) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'banking.read'), false)
    when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'care_plans.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'incidents.read'), false)
    when 'advisory' then exists (select 1 from "better_supabase"."advisories" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'advisories.read'), false)
    when 'advisory_product' then exists (select 1 from "better_supabase"."advisory_products" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant and s."archived_at" is null) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'advisories.read'), false)
    when 'vulnerability' then exists (select 1 from "better_supabase"."vulnerabilities" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'advisories.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'content.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."organization_id" = reaction_subject_visible.tenant and s."archived_at" is null) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant and s."archived_at" is null and (coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'organization' then exists (select 1 from "public"."organizations" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."id" = reaction_subject_visible.tenant)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."organization_id" = reaction_subject_visible.tenant)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."organization_id" = reaction_subject_visible.tenant and s."deleted_at" is null)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."organization_id" = reaction_subject_visible.tenant)
    else false
  end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.register_funding_deliveries_from_time (
  tenant uuid,
  since  date,
  until  date
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_entry record;
  v_awards uuid[];
  v_units numeric;
  v_award uuid;
  v_unit text;
  v_delivery jsonb;
  v_registered jsonb := '[]'::jsonb;
  v_unmatched jsonb := '[]'::jsonb;
begin
  if register_funding_deliveries_from_time.since is null or register_funding_deliveries_from_time.until is null
    or register_funding_deliveries_from_time.until < register_funding_deliveries_from_time.since then
    raise exception 'since and until are days, until on or after since' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  for v_entry in
    select x."id"::text as id, x."subject_type" as subject_type, x."subject_id"::text as subject_id,
      (x."started_at" at time zone 'UTC')::date as day,
      extract(epoch from x."ended_at" - x."started_at") as seconds,
      x."user_id" as performer, null::text as category
    from "better_supabase"."time_entries" x
    where x."tenant_id" = register_funding_deliveries_from_time.tenant
      and x."ended_at" is not null and x."archived_at" is null
      and x."subject_type" is not null
      and x."started_at" >= (register_funding_deliveries_from_time.since::timestamp at time zone 'UTC')
      and x."started_at" < ((register_funding_deliveries_from_time.until + 1)::timestamp at time zone 'UTC')
      and exists (
        select 1 from "better_supabase"."timesheets" s
        where s."tenant_id" = x."tenant_id" and s."user_id" = x."user_id"
          and s."week" = "better_supabase"."time_week"(x."started_at") and s."approved_at" is not null
      )
      and not exists (
        select 1 from "better_supabase"."funding_deliveries" z
        where z."tenant_id" = x."tenant_id" and z."source_type" = 'time_entry' and z."source_id" = x."id"::text
      )
    order by x."started_at", x."id"
  loop
    select array_agg(a."id" order by a."id"), min(y."unit") into v_awards, v_unit
    from "better_supabase"."funding_awards" a
    join "better_supabase"."funding_products" y on y."tenant_id" = a."tenant_id" and y."id" = a."product_id"
    where a."tenant_id" = register_funding_deliveries_from_time.tenant
      and a."subject_type" = v_entry.subject_type and a."subject_id" = v_entry.subject_id
      and a."status" = 'active'
      and v_entry.day >= a."starts_on" and v_entry.day <= coalesce(a."ends_on", v_entry.day)
      and (y."valid_from" is null or v_entry.day >= y."valid_from")
      and (y."valid_until" is null or v_entry.day <= y."valid_until");
    if coalesce(cardinality(v_awards), 0) <> 1 then
      v_unmatched := v_unmatched || jsonb_build_array(jsonb_build_object(
        'entryId', v_entry.id,
        'subjectType', v_entry.subject_type,
        'subjectId', v_entry.subject_id,
        'deliveredOn', v_entry.day,
        'reason', case when coalesce(cardinality(v_awards), 0) = 0 then 'no_award' else 'several_awards' end
      ));
      continue;
    end if;
    v_award := v_awards[1];
    v_units := case v_unit
      when 'minute' then round(v_entry.seconds / 60, 2)
      when 'hour' then round(v_entry.seconds / 3600, 4)
      else 1
    end;
    if v_units <= 0 then
      v_unmatched := v_unmatched || jsonb_build_array(jsonb_build_object(
        'entryId', v_entry.id,
        'subjectType', v_entry.subject_type,
        'subjectId', v_entry.subject_id,
        'deliveredOn', v_entry.day,
        'reason', 'no_duration'
      ));
      continue;
    end if;
    v_delivery := "better_supabase"."register_funding_delivery"(v_award, v_entry.day, v_units, 'time_entry', v_entry.id, v_entry.performer, null);
    v_registered := v_registered || jsonb_build_array(v_delivery);
  end loop;
  return jsonb_build_object('registered', v_registered, 'unmatched', v_unmatched);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.restore_activity (
  activity uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."activities";
  v_id uuid;
  v_tenant uuid;
  v_type text;
  v_subjects jsonb;
  v_first jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  v_id := restore_activity.activity;
  select * into v_row from "better_supabase"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) for update;
  if v_row."id" is null then
    raise exception 'no such activity you can edit' using errcode = 'P0002', hint = 'ACTIVITY_NOT_FOUND';
  end if;
  v_tenant := v_row."tenant_id";
  v_type := v_row."type";
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."activity_subjects" sx where sx."activity_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  if v_row."archived_at" is null then
    return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."activity_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."activities" x where x."id" = v_id);
  end if;
  update "better_supabase"."activities" x set
    "archived_at" = null,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('activity.restored', jsonb_build_object('organizationId', v_tenant, 'activityId', v_id, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects), 'activities/' || v_id::text, (v_tenant::text)::text, null, 'better-supabase/activities');
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."activity_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."activities" x where x."id" = v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.restore_time_entry (
  entry_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."time_entries"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."time_entries" x where x."id" = restore_time_entry.entry_id for update;
  if not found then
    raise exception 'time entry not found' using errcode = 'P0002', hint = 'TIME_ENTRY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(v_row."user_id" = auth.uid(), false) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'time_entries.track'), false)) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'time_entries.manage'), false)) then
    raise exception 'not allowed to change this entry' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if v_row."archived_at" is null then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
  end if;
  if exists (
    select 1 from "better_supabase"."time_entries" x
    where x."tenant_id" = v_row."tenant_id" and x."user_id" = v_row."user_id" and x."id" <> v_row."id"
      and x."archived_at" is null
      and tstzrange(x."started_at", coalesce(x."ended_at", 'infinity'::timestamptz)) && tstzrange(v_row."started_at", coalesce(v_row."ended_at", 'infinity'::timestamptz))
  ) then
    raise exception 'this time overlaps another entry' using errcode = '23P01', hint = 'TIME_ENTRY_OVERLAP';
  end if;
  update "better_supabase"."time_entries" x set
    "archived_at" = null,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('time_entry.restored', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'id', v_row."id", 'userId', v_row."user_id", 'startedAt', v_row."started_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency"), 'time-entries/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/time-entries');
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.restore_trash (
  item_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_root "better_supabase"."trash_items"%rowtype;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select r.* into v_root from "better_supabase"."trash_items" i
    join "better_supabase"."trash_items" r on r."batch_id" = i."batch_id" and r."depth" = 0
    where i."id" = restore_trash.item_id;
  if not found then
    raise exception 'trash item not found' using errcode = 'P0002', hint = 'TRASH_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_root."tenant_id", 'trash.restore'), false) and case v_root."subject_type"
    when 'message' then coalesce(better_supabase.can('tenant', v_root."tenant_id", 'messages.send'), false)
    when 'conversation' then coalesce(better_supabase.can('tenant', v_root."tenant_id", 'messages.send'), false)
    when 'deal' then coalesce(better_supabase.can('tenant', v_root."tenant_id", 'deals.write'), false)
    when 'activity' then coalesce(better_supabase.can('tenant', v_root."tenant_id", 'activities.write'), false)
    when 'work_item' then coalesce(better_supabase.can('tenant', v_root."tenant_id", 'tasks.write'), false)
    when 'risk' then coalesce(better_supabase.can('tenant', v_root."tenant_id", 'risks.write'), false)
    when 'case' then coalesce(better_supabase.can('tenant', v_root."tenant_id", 'cases.write'), false)
    when 'inspection_program' then coalesce(better_supabase.can('tenant', v_root."tenant_id", 'inspections.manage'), false)
    when 'tax_code' then coalesce(better_supabase.can('tenant', v_root."tenant_id", 'tax.manage'), false)
    when 'work_center' then coalesce(better_supabase.can('tenant', v_root."tenant_id", 'manufacturing.manage'), false)
    when 'bank_account' then coalesce(better_supabase.can('tenant', v_root."tenant_id", 'banking.manage'), false)
    when 'advisory_product' then coalesce(better_supabase.can('tenant', v_root."tenant_id", 'advisories.write'), false)
    when 'customer' then coalesce(better_supabase.can('tenant', v_root."tenant_id", 'customers.write'), false)
    when 'drive_node' then coalesce(better_supabase.can('tenant', v_root."tenant_id", 'drive.manage'), false)
    else true
  end)) then
    raise exception 'not allowed to restore this record' using errcode = '42501', hint = 'TRASH_FORBIDDEN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_untrash"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_root."id";
    end if;
  end;
  v_count := "better_supabase"."trash_restore_batch"(v_root."batch_id");
  delete from "better_supabase"."trash_items" where "batch_id" = v_root."batch_id";
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_untrash"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using v_root."id", v_root."batch_id";
    end if;
  end;
  return jsonb_build_object('id', v_root."id", 'batchId', v_root."batch_id", 'subjectType', v_root."subject_type", 'subjectId', v_root."subject_id", 'count', v_count);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.running_timer (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'startedAt', x."started_at", 'endedAt', x."ended_at", 'seconds', case when x."ended_at" is null then null else extract(epoch from x."ended_at" - x."started_at")::bigint end, 'billable', x."billable", 'rate', x."rate"::text, 'rateCurrency', x."rate_currency", 'note', x."note", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") from "better_supabase"."time_entries" x
  where x."tenant_id" = running_timer.tenant and x."user_id" = auth.uid() and x."ended_at" is null;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.running_timers (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'startedAt', x."started_at", 'endedAt', x."ended_at", 'seconds', case when x."ended_at" is null then null else extract(epoch from x."ended_at" - x."started_at")::bigint end, 'billable', x."billable", 'rate', x."rate"::text, 'rateCurrency', x."rate_currency", 'note', x."note", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") order by x."started_at" desc), '[]'::jsonb) from "better_supabase"."time_entries" x
  where x."tenant_id" = running_timers.tenant and x."user_id" = auth.uid() and x."ended_at" is null;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_activity_notes (
  activity uuid,
  notes    jsonb
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
  v_item jsonb;
  v_task uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."type" into v_tenant, v_type
  from "better_supabase"."activities" x where x."id" = save_activity_notes.activity and ((auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and x."archived_at" is null);
  if v_tenant is null then
    raise exception 'no such activity you can edit' using errcode = 'P0002', hint = 'ACTIVITY_NOT_FOUND';
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
  insert into "better_supabase"."activity_notes" ("activity_id", "tenant_id", "summary", "model", "source", "created_by")
  values (save_activity_notes.activity, v_tenant, v_summary, nullif(save_activity_notes.notes ->> 'model', ''), case when save_activity_notes.notes ->> 'source' = 'member' then 'member' else 'ai' end, auth.uid())
  on conflict ("activity_id") do update set
    "summary" = excluded."summary",
    "model" = excluded."model", "source" = excluded."source", "updated_at" = now();
  for v_item in select i.value from jsonb_array_elements(v_items) i loop
    if not exists (
      select 1 from "better_supabase"."activity_note_actions" ax join "better_supabase"."work_items" k on k."id" = ax."task_id"
      where ax."activity_id" = save_activity_notes.activity and k."title" = left(btrim(v_item ->> 'text'), 500)
    ) then
      v_task := ("better_supabase"."create_work_item"(
        v_tenant,
        jsonb_strip_nulls(jsonb_build_object('title', left(btrim(v_item ->> 'text'), 500), 'dueAt', v_item ->> 'dueAt')),
        case when nullif(v_item ->> 'ownerId', '') is null then '{}'::uuid[] else array[(v_item ->> 'ownerId')::uuid] end
      ) ->> 'id')::uuid;
      insert into "better_supabase"."activity_note_actions" ("tenant_id", "activity_id", "task_id")
      values (v_tenant, save_activity_notes.activity, v_task);
    end if;
  end loop;
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."activity_subjects" sx where sx."activity_id" = save_activity_notes.activity), '[]'::jsonb);
  v_first := v_subjects -> 0;
  perform "better_supabase".emit_event('activity.summarized', jsonb_build_object('organizationId', v_tenant, 'activityId', save_activity_notes.activity, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects), 'activities/' || save_activity_notes.activity::text, (v_tenant::text)::text, 'activity.summarized:' || save_activity_notes.activity::text || ':' || md5(save_activity_notes.notes::text), 'better-supabase/activities');
  return (select jsonb_build_object('activityId', nx."activity_id", 'organizationId', nx."tenant_id", 'summary', nx."summary", 'actionTaskIds', coalesce((select jsonb_agg(ax."task_id" order by ax."created_at", ax."id") from "better_supabase"."activity_note_actions" ax where ax."activity_id" = nx."activity_id"), '[]'::jsonb), 'model', nx."model", 'source', nx."source", 'createdBy', nx."created_by", 'createdAt', nx."created_at", 'updatedAt', nx."updated_at") from "better_supabase"."activity_notes" nx where nx."activity_id" = save_activity_notes.activity);
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
  v_activity uuid;
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
  select rx."activity_id", rx."tenant_id", x."type" into v_activity, v_tenant, v_type
  from "better_supabase"."activity_recordings" rx
  join "better_supabase"."activities" x on x."id" = rx."activity_id"
  where rx."id" = v_recording and ((auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and x."archived_at" is null)
  for update of rx;
  if v_activity is null then
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
  delete from "better_supabase"."activity_transcript_segments" sx where sx."recording_id" = v_recording;
  insert into "better_supabase"."activity_transcript_segments" ("recording_id", "tenant_id", "position", "speaker", "speaker_id", "starts_ms", "ends_ms", "text", "confidence")
  select v_recording, v_tenant, i.ordinality::integer, nullif(i.value ->> 'speaker', ''), nullif(i.value ->> 'speakerUserId', '')::uuid, round((i.value ->> 'startMs')::numeric)::integer, round((i.value ->> 'endMs')::numeric)::integer, i.value ->> 'text', (i.value ->> 'confidence')::real
  from jsonb_array_elements(save_activity_transcript.segments) with ordinality i;
  update "better_supabase"."activity_recordings" rx set
    "status" = 'transcribed',
    "error" = null,
    "language" = coalesce(nullif(save_activity_transcript.attrs ->> 'language', ''), rx."language"),
    "duration_seconds" = coalesce((save_activity_transcript.attrs ->> 'durationSeconds')::integer, rx."duration_seconds"),
    "model" = coalesce(nullif(save_activity_transcript.attrs ->> 'model', ''), rx."model"),
    "transcribed_at" = now()
  where rx."id" = v_recording;
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."activity_subjects" sx where sx."activity_id" = v_activity), '[]'::jsonb);
  v_first := v_subjects -> 0;
  perform "better_supabase".emit_event('activity.transcribed', jsonb_build_object('organizationId', v_tenant, 'activityId', v_activity, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects, 'recordingId', v_recording), 'activities/' || v_activity::text, (v_tenant::text)::text, 'activity.transcribed:' || v_recording::text || ':' || md5(save_activity_transcript.segments::text), 'better-supabase/activities');
  return (select jsonb_build_object('id', rx."id", 'organizationId', rx."tenant_id", 'activityId', rx."activity_id", 'fileId', rx."file_id", 'filename', rx."filename", 'mediaType', rx."media_type", 'status', rx."status", 'language', rx."language", 'durationSeconds', rx."duration_seconds", 'error', rx."error", 'model', rx."model", 'segmentCount', (select count(*)::integer from "better_supabase"."activity_transcript_segments" sc where sc."recording_id" = rx."id"), 'createdBy', rx."created_by", 'createdAt', rx."created_at", 'transcribedAt', rx."transcribed_at") from "better_supabase"."activity_recordings" rx where rx."id" = v_recording);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.search_refresh (
  subject_type text,
  subject_id   text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_title text;
  v_body text;
  v_url text;
  v_facets jsonb;
  v_found boolean := false;
  v_hash text;
begin
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_search_document_index"(text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text)', v_hook::oid::regproc)
        using search_refresh.subject_type, search_refresh.subject_id;
    end if;
  end;
  case search_refresh.subject_type
    when 'message' then
      select s."tenant_id", s."body"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."messages" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'conversation' then
      select s."tenant_id", s."title"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."conversations" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'channel' then
      select s."tenant_id", s."name"::text, nullif(concat_ws(E'\n', s."topic"::text, s."purpose"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."channels" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'company' then
      select s."tenant_id", s."name"::text, nullif(concat_ws(E'\n', s."domain"::text, s."website"::text), ''), '/crm/contacts/' || s."id"::text, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."companies" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'person' then
      select s."tenant_id", s."name"::text, nullif(concat_ws(E'\n', s."email"::text, s."phone"::text, s."title"::text), ''), '/crm/contacts/' || s."id"::text, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."people" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'deal' then
      select s."tenant_id", s."name"::text, nullif(concat_ws(E'\n', s."identifier"::text, s."note"::text), ''), '/crm/deals', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."deals" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'course' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."summary"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."courses" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'post' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."body"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."posts" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'activity' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."body"::text, s."outcome"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."activities" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'quote' then
      select s."tenant_id", s."title"::text, null, '/crm/quotes/' || s."id"::text, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."quotes" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'work_item' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."identifier"::text, s."body"::text), ''), '/work', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."work_items" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'employee' then
      select s."tenant_id", s."name"::text, nullif(concat_ws(E'\n', s."email"::text, s."job_title"::text), ''), '/people/' || s."id"::text, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."employees" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'ledger_account' then
      select s."tenant_id", s."name"::text, null, '/finance', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."ledger_accounts" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'invoice' then
      select s."tenant_id", s."title"::text, null, '/finance/payables', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."invoices" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'product' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."description"::text, s."slug"::text), ''), '/shop', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."products" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'product_variant' then
      select s."tenant_id", s."sku"::text, nullif(concat_ws(E'\n', s."title"::text, s."barcode"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."product_variants" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'rfq' then
      select s."tenant_id", s."title"::text, null, '/rfqs', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."rfqs" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'till' then
      select s."tenant_id", s."name"::text, null, '/tills', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."tills" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'order' then
      select s."tenant_id", s."number"::text, null, '/shop/orders/' || s."id"::text, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."orders" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'calendar_event' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."description"::text, s."location"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."calendar_events" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'booking' then
      select s."tenant_id", s."customer_name"::text, null, '/calendar', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."bookings" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'asset' then
      select s."tenant_id", s."name"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."assets" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'asset_location' then
      select s."tenant_id", s."name"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."asset_locations" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'lease' then
      select s."tenant_id", s."title"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."leases" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'expense_report' then
      select s."tenant_id", s."title"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."expense_reports" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'expense_line' then
      select s."tenant_id", s."description"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."expense_lines" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'donation_fund' then
      select s."tenant_id", s."name"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."donation_funds" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'warranty_claim' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."manufacturer"::text, s."decision"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."warranty_claims" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'work_order' then
      select s."tenant_id", s."title"::text, null, '/field/dispatch', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."work_orders" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'shipment' then
      select s."tenant_id", s."reference"::text, null, '/field/shipments', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."shipments" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'contract' then
      select s."tenant_id", s."title"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."contracts" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'control' then
      select s."tenant_id", s."title"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."controls" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'compliance_policy' then
      select s."tenant_id", s."title"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."compliance_policies" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'qualification_type' then
      select s."tenant_id", s."name"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."qualification_types" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'risk' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."number"::text, s."description"::text, s."cause"::text, s."consequence"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."risks" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'case' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."number"::text, s."description"::text, s."root_cause"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."cases" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'inspection' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."number"::text, s."scope"::text, s."summary"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."inspections" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'inspection_program' then
      select s."tenant_id", s."name"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."inspection_programs" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'inspection_finding' then
      select s."tenant_id", s."title"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."inspection_findings" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'form' then
      select s."tenant_id", s."title"::text, null, '/forms/' || s."id"::text, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."forms" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'meeting' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."location"::text, s."summary"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."meetings" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'meeting_decision' then
      select s."tenant_id", s."title"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."meeting_decisions" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'maintenance_plan' then
      select s."tenant_id", s."title"::text, null, '/maintenance', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."maintenance_plans" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'dam_usage_right' then
      select s."tenant_id", s."licensee"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."dam_usage_rights" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'lims_sample' then
      select s."tenant_id", s."title"::text, null, '/lims', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."lims_samples" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'tax_code' then
      select s."tenant_id", s."name"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."tax_codes" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'production_order' then
      select s."tenant_id", s."number"::text, nullif(concat_ws(E'\n', s."note"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."production_orders" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'work_center' then
      select s."tenant_id", s."name"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."work_centers" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'bank_account' then
      select s."tenant_id", s."name"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."bank_accounts" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'care_plan' then
      select s."tenant_id", s."title"::text, null, '/care-plans', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."care_plans" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'incident' then
      select s."tenant_id", s."title"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."incidents" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'advisory' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."tracking_id"::text, s."summary"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."advisories" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'advisory_product' then
      select s."tenant_id", s."name"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."advisory_products" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'vulnerability' then
      select s."tenant_id", s."vuln_id"::text, nullif(concat_ws(E'\n', s."summary"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."vulnerabilities" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'content_entry' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."summary"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."content_entries" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'document' then
      select s."tenant_id", s."name"::text, null, '/documents/' || s."id"::text, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."documents" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'customer' then
      select s."organization_id", s."name"::text, null, '/customers/' || s."id"::text, jsonb_strip_nulls(jsonb_build_object('status', s."status"))
        into v_tenant, v_title, v_body, v_url, v_facets
        from "public"."customers" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'drive_node' then
      select s."tenant_id", f."name"::text, nullif(concat_ws(E'\n', f."content"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."drive_nodes" s
        join "better_supabase"."drive_node_search" f on f."id" = s."id"
        where s."id" = (search_refresh.subject_id)::uuid
        and f."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'project' then
      select s."organization_id", s."name"::text, null, '/projects/' || s."id"::text, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "public"."projects" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."deleted_at" is null;
      v_found := found;
    when 'task' then
      select s."organization_id", s."title"::text, null, '/projects/' || s."project_id"::text, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "public"."tasks" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    else
      raise exception 'this subject type has no search entry in config.recordTypes' using errcode = '22023', hint = 'SEARCH_SUBJECT_UNKNOWN';
  end case;
  if not v_found then
    delete from "better_supabase"."search_documents"
    where "subject_type" = search_refresh.subject_type and "subject_id" = search_refresh.subject_id;
    return false;
  end if;
  v_hash := md5(coalesce(v_title, '') || E'\x1f' || coalesce(v_body, ''));
  insert into "better_supabase"."search_documents" ("tenant_id", "subject_type", "subject_id", "title", "title_search", "body", "url", "tsv", "content_hash", "updated_at", "facets", "sort_key")
  values (
    v_tenant, search_refresh.subject_type, search_refresh.subject_id, v_title, "better_supabase"."search_normalize"(v_title), v_body, v_url,
    setweight(to_tsvector('simple', "better_supabase"."search_normalize"(v_title)), 'A')
      || setweight(to_tsvector('simple', "better_supabase"."search_normalize"(v_body)), 'B'),
    v_hash, now(), v_facets, left("better_supabase"."search_normalize"(v_title), 200)
  )
  on conflict ("subject_type", "subject_id") do update set
    "tenant_id" = excluded."tenant_id",
    "title" = excluded."title",
    "title_search" = excluded."title_search",
    "body" = excluded."body",
    "url" = excluded."url",
    "tsv" = excluded."tsv",
    "content_hash" = excluded."content_hash",
    "facets" = excluded."facets",
    "sort_key" = excluded."sort_key",
    "updated_at" = now()
  where ("better_supabase"."search_documents"."tenant_id", "better_supabase"."search_documents"."title", "better_supabase"."search_documents"."body", "better_supabase"."search_documents"."url", "better_supabase"."search_documents"."facets")
    is distinct from (excluded."tenant_id", excluded."title", excluded."body", excluded."url", excluded."facets");
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_search_document_index"(text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text)', v_hook::oid::regproc)
        using search_refresh.subject_type, search_refresh.subject_id;
    end if;
  end;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.start_timer (
  tenant        uuid,
  subject_type  text    DEFAULT NULL::text,
  subject_id    text    DEFAULT NULL::text,
  billable      boolean DEFAULT false,
  rate          bigint  DEFAULT NULL::bigint,
  rate_currency text    DEFAULT NULL::text,
  note          text    DEFAULT NULL::text
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
  v_row "better_supabase"."time_entries"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null or not coalesce(better_supabase.can('tenant', start_timer.tenant, 'time_entries.track'), false) then
    raise exception 'not allowed to track time here' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if (start_timer.subject_type is null) <> (start_timer.subject_id is null) then
    raise exception 'name both subject_type and subject_id, or neither' using errcode = '22023', hint = 'TIME_SUBJECT_INVALID';
  end if;
  if start_timer.subject_type is not null and start_timer.subject_type <> all (array['company', 'project']::text[]) then
    raise exception 'time is tracked on company, project records' using errcode = '22023', hint = 'TIME_SUBJECT_INVALID';
  end if;
  if start_timer.subject_type is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case start_timer.subject_type
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'contacts.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'contacts.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'posts.read'), false)
    when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'activities.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'tasks.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'ledger.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'invoices.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'catalog.read'), false)
    when 'rfq' then exists (select 1 from "better_supabase"."rfqs" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'rfqs.read'), false)
    when 'till' then exists (select 1 from "better_supabase"."tills" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'tills.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'donations.read'), false)
    when 'warranty_claim' then exists (select 1 from "better_supabase"."warranty_claims" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'warranty.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'compliance.read'), false)
    when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'compliance.read'), false)
    when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'qualifications.read'), false)
    when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'risks.read'), false)
    when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'cases.read'), false)
    when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'inspections.read'), false)
    when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'inspections.read'), false)
    when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'inspections.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'forms.read'), false)
    when 'meeting' then exists (select 1 from "better_supabase"."meetings" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'meetings.read'), false)
    when 'meeting_decision' then exists (select 1 from "better_supabase"."meeting_decisions" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'meetings.read'), false)
    when 'maintenance_plan' then exists (select 1 from "better_supabase"."maintenance_plans" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'maintenance.read'), false)
    when 'dam_usage_right' then exists (select 1 from "better_supabase"."dam_usage_rights" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'dam.read'), false)
    when 'lims_sample' then exists (select 1 from "better_supabase"."lims_samples" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'lims.read'), false)
    when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'tax.read'), false)
    when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'manufacturing.read'), false)
    when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'manufacturing.read'), false)
    when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'banking.read'), false)
    when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'care_plans.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'incidents.read'), false)
    when 'advisory' then exists (select 1 from "better_supabase"."advisories" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'advisories.read'), false)
    when 'advisory_product' then exists (select 1 from "better_supabase"."advisory_products" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'advisories.read'), false)
    when 'vulnerability' then exists (select 1 from "better_supabase"."vulnerabilities" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'advisories.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'content.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (start_timer.subject_id)::uuid and s."organization_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant and (coalesce(better_supabase.can('tenant', start_timer.tenant, 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'organization' then exists (select 1 from "public"."organizations" s where s."id" = (start_timer.subject_id)::uuid and s."id" = start_timer.tenant)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (start_timer.subject_id)::uuid and s."organization_id" = start_timer.tenant)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (start_timer.subject_id)::uuid and s."organization_id" = start_timer.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (start_timer.subject_id)::uuid and s."organization_id" = start_timer.tenant)
    else false
  end) then
    raise exception 'not allowed to track time on this record' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if start_timer.rate is not null and start_timer.rate_currency is null then
    raise exception 'a rate needs rate_currency' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  if start_timer.rate_currency !~ '^[A-Z]{3}$' then
    raise exception 'rate_currency must be a three-letter currency code' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('time_entry:' || start_timer.tenant::text || ':' || v_me::text, 0));
  update "better_supabase"."time_entries" x set "ended_at" = v_at, "updated_at" = v_at
    where x."tenant_id" = start_timer.tenant and x."user_id" = v_me and x."ended_at" is null
    returning * into v_row;
  if found then
    perform "better_supabase".emit_event('time_entry.recorded', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'id', v_row."id", 'userId', v_row."user_id", 'startedAt', v_row."started_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency"), 'time-entries/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/time-entries');
  end if;
  v_row := null;
  v_row."id" := gen_random_uuid();
  v_row."tenant_id" := start_timer.tenant;
  v_row."user_id" := v_me;
  v_row."subject_type" := start_timer.subject_type;
  v_row."subject_id" := start_timer.subject_id;
  v_row."started_at" := v_at;
  v_row."billable" := coalesce(start_timer.billable, false);
  v_row."rate" := start_timer.rate;
  v_row."rate_currency" := start_timer.rate_currency;
  v_row."note" := start_timer.note;
  if exists (
    select 1 from "better_supabase"."time_entries" x
    where x."tenant_id" = v_row."tenant_id" and x."user_id" = v_row."user_id" and x."id" <> v_row."id"
      and x."archived_at" is null
      and tstzrange(x."started_at", coalesce(x."ended_at", 'infinity'::timestamptz)) && tstzrange(v_row."started_at", coalesce(v_row."ended_at", 'infinity'::timestamptz))
  ) then
    raise exception 'this time overlaps another entry' using errcode = '23P01', hint = 'TIME_ENTRY_OVERLAP';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_time_entry_save"(uuid, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::uuid)', v_hook::oid::regproc)
        using v_row."id", v_row."tenant_id", v_row."user_id";
    end if;
  end;
  insert into "better_supabase"."time_entries" ("id", "tenant_id", "user_id", "subject_type", "subject_id", "started_at", "billable", "rate", "rate_currency", "note")
  values (v_row."id", v_row."tenant_id", v_row."user_id", v_row."subject_type", v_row."subject_id", v_row."started_at", v_row."billable", v_row."rate", v_row."rate_currency", v_row."note")
  returning * into v_row;
  perform "better_supabase".emit_event('time_entry.started', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'id', v_row."id", 'userId', v_row."user_id", 'startedAt', v_row."started_at"), 'time-entries/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/time-entries');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_time_entry_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.stop_timer (
  tenant uuid,
  entry  uuid DEFAULT NULL::uuid
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
  v_row "better_supabase"."time_entries"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."time_entries" x
    where x."tenant_id" = stop_timer.tenant and x."user_id" = v_me and x."ended_at" is null
      and (stop_timer.entry is null or x."id" = stop_timer.entry)
    order by x."started_at" desc
    limit 1
    for update;
  if not found then
    raise exception 'no timer is running' using errcode = 'P0002', hint = 'TIME_NO_TIMER';
  end if;
  update "better_supabase"."time_entries" x set "ended_at" = v_at, "updated_at" = v_at
    where x."id" = v_row."id"
    returning * into v_row;
  perform "better_supabase".emit_event('time_entry.recorded', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'id', v_row."id", 'userId', v_row."user_id", 'startedAt', v_row."started_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency"), 'time-entries/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/time-entries');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_time_entry_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.subject_title (
  subject_type text,
  subject_id   text
)
  RETURNS text
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
begin
  case subject_title.subject_type
    when 'message' then
      return (select s."body"::text from "better_supabase"."messages" s where s."id" = (subject_title.subject_id)::uuid and s."archived_at" is null);
    when 'conversation' then
      return (select s."title"::text from "better_supabase"."conversations" s where s."id" = (subject_title.subject_id)::uuid and s."archived_at" is null);
    when 'channel' then
      return (select s."name"::text from "better_supabase"."channels" s where s."id" = (subject_title.subject_id)::uuid);
    when 'company' then
      return (select s."name"::text from "better_supabase"."companies" s where s."id" = (subject_title.subject_id)::uuid);
    when 'person' then
      return (select s."name"::text from "better_supabase"."people" s where s."id" = (subject_title.subject_id)::uuid);
    when 'deal' then
      return (select s."name"::text from "better_supabase"."deals" s where s."id" = (subject_title.subject_id)::uuid and s."archived_at" is null);
    when 'course' then
      return (select s."title"::text from "better_supabase"."courses" s where s."id" = (subject_title.subject_id)::uuid);
    when 'post' then
      return (select s."title"::text from "better_supabase"."posts" s where s."id" = (subject_title.subject_id)::uuid);
    when 'activity' then
      return (select s."title"::text from "better_supabase"."activities" s where s."id" = (subject_title.subject_id)::uuid and s."archived_at" is null);
    when 'quote' then
      return (select s."title"::text from "better_supabase"."quotes" s where s."id" = (subject_title.subject_id)::uuid);
    when 'work_item' then
      return (select s."title"::text from "better_supabase"."work_items" s where s."id" = (subject_title.subject_id)::uuid and s."archived_at" is null);
    when 'employee' then
      return (select s."name"::text from "better_supabase"."employees" s where s."id" = (subject_title.subject_id)::uuid);
    when 'ledger_account' then
      return (select s."name"::text from "better_supabase"."ledger_accounts" s where s."id" = (subject_title.subject_id)::uuid);
    when 'invoice' then
      return (select s."title"::text from "better_supabase"."invoices" s where s."id" = (subject_title.subject_id)::uuid);
    when 'product' then
      return (select s."title"::text from "better_supabase"."products" s where s."id" = (subject_title.subject_id)::uuid);
    when 'product_variant' then
      return (select s."sku"::text from "better_supabase"."product_variants" s where s."id" = (subject_title.subject_id)::uuid);
    when 'rfq' then
      return (select s."title"::text from "better_supabase"."rfqs" s where s."id" = (subject_title.subject_id)::uuid);
    when 'till' then
      return (select s."name"::text from "better_supabase"."tills" s where s."id" = (subject_title.subject_id)::uuid);
    when 'order' then
      return (select s."number"::text from "better_supabase"."orders" s where s."id" = (subject_title.subject_id)::uuid);
    when 'calendar_event' then
      return (select s."title"::text from "better_supabase"."calendar_events" s where s."id" = (subject_title.subject_id)::uuid);
    when 'booking' then
      return (select s."customer_name"::text from "better_supabase"."bookings" s where s."id" = (subject_title.subject_id)::uuid);
    when 'asset' then
      return (select s."name"::text from "better_supabase"."assets" s where s."id" = (subject_title.subject_id)::uuid);
    when 'asset_location' then
      return (select s."name"::text from "better_supabase"."asset_locations" s where s."id" = (subject_title.subject_id)::uuid);
    when 'lease' then
      return (select s."title"::text from "better_supabase"."leases" s where s."id" = (subject_title.subject_id)::uuid);
    when 'expense_report' then
      return (select s."title"::text from "better_supabase"."expense_reports" s where s."id" = (subject_title.subject_id)::uuid);
    when 'expense_line' then
      return (select s."description"::text from "better_supabase"."expense_lines" s where s."id" = (subject_title.subject_id)::uuid);
    when 'donation_fund' then
      return (select s."name"::text from "better_supabase"."donation_funds" s where s."id" = (subject_title.subject_id)::uuid);
    when 'warranty_claim' then
      return (select s."title"::text from "better_supabase"."warranty_claims" s where s."id" = (subject_title.subject_id)::uuid);
    when 'work_order' then
      return (select s."title"::text from "better_supabase"."work_orders" s where s."id" = (subject_title.subject_id)::uuid);
    when 'shipment' then
      return (select s."reference"::text from "better_supabase"."shipments" s where s."id" = (subject_title.subject_id)::uuid);
    when 'contract' then
      return (select s."title"::text from "better_supabase"."contracts" s where s."id" = (subject_title.subject_id)::uuid);
    when 'control' then
      return (select s."title"::text from "better_supabase"."controls" s where s."id" = (subject_title.subject_id)::uuid);
    when 'compliance_policy' then
      return (select s."title"::text from "better_supabase"."compliance_policies" s where s."id" = (subject_title.subject_id)::uuid);
    when 'qualification_type' then
      return (select s."name"::text from "better_supabase"."qualification_types" s where s."id" = (subject_title.subject_id)::uuid);
    when 'risk' then
      return (select s."title"::text from "better_supabase"."risks" s where s."id" = (subject_title.subject_id)::uuid and s."archived_at" is null);
    when 'case' then
      return (select s."title"::text from "better_supabase"."cases" s where s."id" = (subject_title.subject_id)::uuid and s."archived_at" is null);
    when 'inspection' then
      return (select s."title"::text from "better_supabase"."inspections" s where s."id" = (subject_title.subject_id)::uuid);
    when 'inspection_program' then
      return (select s."name"::text from "better_supabase"."inspection_programs" s where s."id" = (subject_title.subject_id)::uuid and s."archived_at" is null);
    when 'inspection_finding' then
      return (select s."title"::text from "better_supabase"."inspection_findings" s where s."id" = (subject_title.subject_id)::uuid);
    when 'form' then
      return (select s."title"::text from "better_supabase"."forms" s where s."id" = (subject_title.subject_id)::uuid);
    when 'meeting' then
      return (select s."title"::text from "better_supabase"."meetings" s where s."id" = (subject_title.subject_id)::uuid);
    when 'meeting_decision' then
      return (select s."title"::text from "better_supabase"."meeting_decisions" s where s."id" = (subject_title.subject_id)::uuid);
    when 'maintenance_plan' then
      return (select s."title"::text from "better_supabase"."maintenance_plans" s where s."id" = (subject_title.subject_id)::uuid);
    when 'dam_usage_right' then
      return (select s."licensee"::text from "better_supabase"."dam_usage_rights" s where s."id" = (subject_title.subject_id)::uuid);
    when 'lims_sample' then
      return (select s."title"::text from "better_supabase"."lims_samples" s where s."id" = (subject_title.subject_id)::uuid);
    when 'tax_code' then
      return (select s."name"::text from "better_supabase"."tax_codes" s where s."id" = (subject_title.subject_id)::uuid and s."archived_at" is null);
    when 'production_order' then
      return (select s."number"::text from "better_supabase"."production_orders" s where s."id" = (subject_title.subject_id)::uuid);
    when 'work_center' then
      return (select s."name"::text from "better_supabase"."work_centers" s where s."id" = (subject_title.subject_id)::uuid and s."archived_at" is null);
    when 'bank_account' then
      return (select s."name"::text from "better_supabase"."bank_accounts" s where s."id" = (subject_title.subject_id)::uuid and s."archived_at" is null);
    when 'care_plan' then
      return (select s."title"::text from "better_supabase"."care_plans" s where s."id" = (subject_title.subject_id)::uuid);
    when 'incident' then
      return (select s."title"::text from "better_supabase"."incidents" s where s."id" = (subject_title.subject_id)::uuid);
    when 'advisory' then
      return (select s."title"::text from "better_supabase"."advisories" s where s."id" = (subject_title.subject_id)::uuid);
    when 'advisory_product' then
      return (select s."name"::text from "better_supabase"."advisory_products" s where s."id" = (subject_title.subject_id)::uuid and s."archived_at" is null);
    when 'vulnerability' then
      return (select s."vuln_id"::text from "better_supabase"."vulnerabilities" s where s."id" = (subject_title.subject_id)::uuid);
    when 'content_entry' then
      return (select s."title"::text from "better_supabase"."content_entries" s where s."id" = (subject_title.subject_id)::uuid);
    when 'document' then
      return (select s."name"::text from "better_supabase"."documents" s where s."id" = (subject_title.subject_id)::uuid);
    when 'customer' then
      return (select s."name"::text from "public"."customers" s where s."id" = (subject_title.subject_id)::uuid and s."archived_at" is null);
    when 'drive_node' then
      return (select s."name"::text from "better_supabase"."drive_nodes" s where s."id" = (subject_title.subject_id)::uuid and s."archived_at" is null);
    when 'organization' then
      return (select s."name"::text from "public"."organizations" s where s."id" = (subject_title.subject_id)::uuid);
    when 'change_request' then
      return (select s."title"::text from "public"."change_requests" s where s."id" = (subject_title.subject_id)::uuid);
    when 'project' then
      return (select s."name"::text from "public"."projects" s where s."id" = (subject_title.subject_id)::uuid and s."deleted_at" is null);
    when 'task' then
      return (select s."title"::text from "public"."tasks" s where s."id" = (subject_title.subject_id)::uuid);
    else
      return null;
  end case;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.subject_titles (
  refs jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  found jsonb := '[]'::jsonb;
begin
  if jsonb_typeof(subject_titles.refs) is distinct from 'array' then
    raise exception 'refs must be a JSON array of { type, id }'
      using errcode = '22023', hint = 'SUBJECT_REFS_INVALID';
  end if;
  if jsonb_array_length(subject_titles.refs) > 500 then
    raise exception 'subject_titles takes at most 500 refs'
      using errcode = '22023', hint = 'SUBJECT_REFS_TOO_MANY';
  end if;
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'message', 'id', s."id"::text,
      'title', s."body"::text, 'url', null::text))
    from "better_supabase"."messages" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'message')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'conversation', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."conversations" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'conversation')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'channel', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."channels" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'channel')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'company', 'id', s."id"::text,
      'title', s."name"::text, 'url', '/crm/contacts/' || s."id"::text))
    from "better_supabase"."companies" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'company')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'person', 'id', s."id"::text,
      'title', s."name"::text, 'url', '/crm/contacts/' || s."id"::text))
    from "better_supabase"."people" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'person')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'deal', 'id', s."id"::text,
      'title', s."name"::text, 'url', '/crm/deals'))
    from "better_supabase"."deals" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'deal')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'course', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."courses" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'course')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'post', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."posts" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'post')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'activity', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."activities" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'activity')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'quote', 'id', s."id"::text,
      'title', s."title"::text, 'url', '/crm/quotes/' || s."id"::text))
    from "better_supabase"."quotes" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'quote')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'work_item', 'id', s."id"::text,
      'title', s."title"::text, 'url', '/work'))
    from "better_supabase"."work_items" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'work_item')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'employee', 'id', s."id"::text,
      'title', s."name"::text, 'url', '/people/' || s."id"::text))
    from "better_supabase"."employees" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'employee')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'ledger_account', 'id', s."id"::text,
      'title', s."name"::text, 'url', '/finance'))
    from "better_supabase"."ledger_accounts" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'ledger_account')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'invoice', 'id', s."id"::text,
      'title', s."title"::text, 'url', '/finance/payables'))
    from "better_supabase"."invoices" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'invoice')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'product', 'id', s."id"::text,
      'title', s."title"::text, 'url', '/shop'))
    from "better_supabase"."products" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'product')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'product_variant', 'id', s."id"::text,
      'title', s."sku"::text, 'url', null::text))
    from "better_supabase"."product_variants" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'product_variant')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'rfq', 'id', s."id"::text,
      'title', s."title"::text, 'url', '/rfqs'))
    from "better_supabase"."rfqs" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'rfq')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'till', 'id', s."id"::text,
      'title', s."name"::text, 'url', '/tills'))
    from "better_supabase"."tills" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'till')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'order', 'id', s."id"::text,
      'title', s."number"::text, 'url', '/shop/orders/' || s."id"::text))
    from "better_supabase"."orders" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'order')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'calendar_event', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."calendar_events" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'calendar_event')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'booking', 'id', s."id"::text,
      'title', s."customer_name"::text, 'url', '/calendar'))
    from "better_supabase"."bookings" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'booking')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'asset', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."assets" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'asset')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'asset_location', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."asset_locations" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'asset_location')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'lease', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."leases" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'lease')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'expense_report', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."expense_reports" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'expense_report')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'expense_line', 'id', s."id"::text,
      'title', s."description"::text, 'url', null::text))
    from "better_supabase"."expense_lines" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'expense_line')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'donation_fund', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."donation_funds" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'donation_fund')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'warranty_claim', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."warranty_claims" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'warranty_claim')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'work_order', 'id', s."id"::text,
      'title', s."title"::text, 'url', '/field/dispatch'))
    from "better_supabase"."work_orders" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'work_order')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'shipment', 'id', s."id"::text,
      'title', s."reference"::text, 'url', '/field/shipments'))
    from "better_supabase"."shipments" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'shipment')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'contract', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."contracts" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'contract')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'control', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."controls" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'control')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'compliance_policy', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."compliance_policies" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'compliance_policy')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'qualification_type', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."qualification_types" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'qualification_type')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'risk', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."risks" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'risk')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'case', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."cases" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'case')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'inspection', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."inspections" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'inspection')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'inspection_program', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."inspection_programs" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'inspection_program')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'inspection_finding', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."inspection_findings" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'inspection_finding')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'form', 'id', s."id"::text,
      'title', s."title"::text, 'url', '/forms/' || s."id"::text))
    from "better_supabase"."forms" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'form')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'meeting', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."meetings" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'meeting')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'meeting_decision', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."meeting_decisions" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'meeting_decision')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'maintenance_plan', 'id', s."id"::text,
      'title', s."title"::text, 'url', '/maintenance'))
    from "better_supabase"."maintenance_plans" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'maintenance_plan')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'dam_usage_right', 'id', s."id"::text,
      'title', s."licensee"::text, 'url', null::text))
    from "better_supabase"."dam_usage_rights" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'dam_usage_right')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'lims_sample', 'id', s."id"::text,
      'title', s."title"::text, 'url', '/lims'))
    from "better_supabase"."lims_samples" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'lims_sample')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'tax_code', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."tax_codes" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'tax_code')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'production_order', 'id', s."id"::text,
      'title', s."number"::text, 'url', null::text))
    from "better_supabase"."production_orders" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'production_order')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'work_center', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."work_centers" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'work_center')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'bank_account', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."bank_accounts" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'bank_account')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'care_plan', 'id', s."id"::text,
      'title', s."title"::text, 'url', '/care-plans'))
    from "better_supabase"."care_plans" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'care_plan')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'incident', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."incidents" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'incident')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'advisory', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."advisories" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'advisory')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'advisory_product', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."advisory_products" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'advisory_product')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'vulnerability', 'id', s."id"::text,
      'title', s."vuln_id"::text, 'url', null::text))
    from "better_supabase"."vulnerabilities" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'vulnerability')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'content_entry', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."content_entries" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'content_entry')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'document', 'id', s."id"::text,
      'title', s."name"::text, 'url', '/documents/' || s."id"::text))
    from "better_supabase"."documents" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'document')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'customer', 'id', s."id"::text,
      'title', s."name"::text, 'url', '/customers/' || s."id"::text))
    from "public"."customers" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'customer')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'drive_node', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."drive_nodes" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'drive_node')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'organization', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "public"."organizations" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'organization')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'application', 'id', s."id"::text,
      'title', null::text, 'url', '/people/hiring'))
    from "better_supabase"."applications" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'application')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'change_request', 'id', s."id"::text,
      'title', s."title"::text, 'url', '/change-requests/' || s."id"::text))
    from "public"."change_requests" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'change_request')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'project', 'id', s."id"::text,
      'title', s."name"::text, 'url', '/projects/' || s."id"::text))
    from "public"."projects" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'project')::uuid[]) and s."deleted_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'task', 'id', s."id"::text,
      'title', s."title"::text, 'url', '/projects/' || s."project_id"::text))
    from "public"."tasks" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'task')::uuid[])), '[]'::jsonb);
  return found;
exception
  when invalid_text_representation then
    raise exception 'a subject id does not match its type''s id column'
      using errcode = '22023', hint = 'SUBJECT_ID_INVALID';
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.submit_timesheet (
  tenant uuid,
  week   date,
  note   text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_week date := date_trunc('week', submit_timesheet.week)::date;
  v_sheet "better_supabase"."timesheets"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_request jsonb;
  v_seconds bigint;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null or not coalesce(better_supabase.can('tenant', submit_timesheet.tenant, 'time_entries.track'), false) then
    raise exception 'not allowed to submit a timesheet here' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('time_entry:' || submit_timesheet.tenant::text || ':' || v_me::text, 0));
  if exists (
    select 1 from "better_supabase"."time_entries" x
    where x."tenant_id" = submit_timesheet.tenant and x."user_id" = v_me and x."ended_at" is null
      and "better_supabase"."time_week"(x."started_at") = v_week
  ) then
    raise exception 'stop the running timer before submitting this week' using errcode = '55000', hint = 'TIME_ENTRIES_TIMESHEET_TIMER_RUNNING';
  end if;
  insert into "better_supabase"."timesheets" ("tenant_id", "user_id", "week")
  values (submit_timesheet.tenant, v_me, v_week)
  on conflict ("tenant_id", "user_id", "week") do nothing;
  select * into v_sheet from "better_supabase"."timesheets" s
    where s."tenant_id" = submit_timesheet.tenant and s."user_id" = v_me and s."week" = v_week
    for update;
  if v_sheet."approved_at" is not null then
    raise exception 'this week is already approved' using errcode = '55000', hint = 'TIME_ENTRIES_TIMESHEET_APPROVED';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" x where x."id" = v_sheet."approval_id";
  if v_approval."status" = 'pending' then
    raise exception 'this week is already waiting for approval' using errcode = '55000', hint = 'TIME_ENTRIES_TIMESHEET_SUBMITTED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_timesheet_submit"(uuid, uuid, date)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::date)', v_hook::oid::regproc)
        using v_sheet."id", submit_timesheet.tenant, v_week;
    end if;
  end;
  select coalesce(sum(extract(epoch from x."ended_at" - x."started_at")), 0)::bigint into v_seconds
    from "better_supabase"."time_entries" x
    where x."tenant_id" = submit_timesheet.tenant and x."user_id" = v_me
      and "better_supabase"."time_week"(x."started_at") = v_week and x."archived_at" is null;
  v_request := "better_supabase"."open_approval"(
    submit_timesheet.tenant, 'timesheet', v_sheet."id"::text, 'approve',
    '{"steps":[{"approvers":{"permission":"time_entries.approve"},"required":1}],"selfApproval":false,"expiresIn":null,"run":null}'::jsonb, submit_timesheet.note,
    jsonb_build_object('userId', v_me, 'week', v_week, 'seconds', v_seconds)
  );
  update "better_supabase"."timesheets" s
  set "approval_id" = (v_request ->> 'id')::uuid, "note" = submit_timesheet.note, "submitted_at" = now()
  where s."id" = v_sheet."id"
  returning * into v_sheet;
  select * into v_approval from "better_supabase"."approval_requests" x where x."id" = v_sheet."approval_id";
  perform "better_supabase".emit_event('timesheet.submitted', jsonb_build_object('organizationId', v_sheet."tenant_id", 'id', v_sheet."id", 'userId', v_sheet."user_id", 'week', v_sheet."week", 'approvalId', v_sheet."approval_id"), 'timesheets/' || v_sheet."id"::text, (v_sheet."tenant_id")::text, null, 'better-supabase/time-entries');
  perform better_supabase.audit_event(
    event_type => 'timesheet.submitted',
    category => 'data',
    target_type => 'timesheet',
    record_id => v_sheet."id"::text,
    summary => 'submitted a timesheet' || ' for the week of ' || v_sheet."week"::text,
    tenant => (v_sheet."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_sheet."tenant_id", 'id', v_sheet."id", 'userId', v_sheet."user_id", 'week', v_sheet."week", 'approvalId', v_sheet."approval_id")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_timesheet_submit"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_sheet."id";
    end if;
  end;
  return jsonb_build_object('id', v_sheet."id", 'organizationId', v_sheet."tenant_id", 'userId', v_sheet."user_id", 'week', v_sheet."week", 'status', case when v_sheet."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" = 'rejected' then 'rejected' else 'open' end, 'approvalId', v_sheet."approval_id", 'note', v_sheet."note", 'submittedAt', v_sheet."submitted_at", 'approvedAt', v_sheet."approved_at", 'createdAt', v_sheet."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.time_entry_guard()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  -- Only a change to logged time (options.lockedColumns) touches the week.
  if tg_op = 'UPDATE' and (new."started_at", new."ended_at", new."subject_type", new."subject_id", new."user_id", new."rate", new."rate_currency", new."archived_at") is not distinct from (old."started_at", old."ended_at", old."subject_type", old."subject_id", old."user_id", old."rate", old."rate_currency", old."archived_at") then
    return new;
  end if;
  if tg_op in ('UPDATE', 'DELETE') and "better_supabase"."time_week_locked"(old."tenant_id", old."user_id", old."started_at") then
    raise exception 'this week''s timesheet is submitted or approved' using errcode = '55000', hint = 'TIME_PERIOD_LOCKED';
  end if;
  if tg_op in ('INSERT', 'UPDATE') and "better_supabase"."time_week_locked"(new."tenant_id", new."user_id", new."started_at") then
    raise exception 'this week''s timesheet is submitted or approved' using errcode = '55000', hint = 'TIME_PERIOD_LOCKED';
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.time_lines_for_invoice (
  tenant   uuid,
  scope    jsonb,
  group_by text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_scope jsonb := coalesce(time_lines_for_invoice.scope, '{}'::jsonb);
  v_group text := coalesce(time_lines_for_invoice.group_by, 'subject');
begin
  if v_group not in ('subject', 'member', 'entry') then
    raise exception 'group_by is subject, member or entry' using errcode = '22023', hint = 'BILLABLE_TIME_GROUPING_INVALID';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('description', l.description, 'quantity', l.quantity::text, 'unitAmount', l.rate::text,
      'currency', l.currency, 'entryIds', l.entry_ids) order by l.first_at)
    from (
    select min(u.started_at) as first_at, u.currency, u.rate,
      round(sum(u.seconds) / 3600.0, 4) as quantity,
      jsonb_agg(u.id order by u.started_at, u.id) as entry_ids,
      case when v_group = 'entry' then min(u.user_id::text) end as user_text,
      case when v_group = 'member' then min(u.user_id::text) end as member_text,
      min(u.subject_type) as subject_type, min(u.subject_id) as subject_id,
      case
        when v_group = 'entry' then coalesce(min(u.note), 'Time on ' || to_char(min(u.started_at) at time zone 'UTC', 'YYYY-MM-DD'))
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
    where x."tenant_id" = time_lines_for_invoice.tenant
      and x."billable" and x."ended_at" is not null and x."archived_at" is null
      and not exists (select 1 from "better_supabase"."time_invoice_entries" d where d."entry_id" = x."id")
      and (v_scope -> 'subject' is null or (x."subject_type" = v_scope -> 'subject' ->> 'type' and x."subject_id" = v_scope -> 'subject' ->> 'id'))
      and (v_scope ->> 'userId' is null or x."user_id" = (v_scope ->> 'userId')::uuid)
      and (v_scope ->> 'starts' is null or x."started_at" >= (v_scope ->> 'starts')::timestamptz)
      and (v_scope ->> 'ends' is null or x."started_at" < (v_scope ->> 'ends')::timestamptz)
      and (v_scope -> 'entryIds' is null or x."id"::text in (select jsonb_array_elements_text(v_scope -> 'entryIds')))) u
    where u.rate is not null
    group by u.currency, u.rate, u.subject_type, u.subject_id,
      case when v_group in ('member', 'entry') then u.user_id end,
      case when v_group = 'entry' then u.id end
    having round(sum(u.seconds) / 3600.0, 4) > 0) l), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.trash (
  tenant       uuid,
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_batch uuid := gen_random_uuid();
  v_count integer;
  v_id uuid;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', trash.tenant, 'trash.create'), false) and case trash.subject_type
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (trash.subject_id)::uuid and s."tenant_id" = trash.tenant) and coalesce(better_supabase.can('tenant', trash.tenant, 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (trash.subject_id)::uuid and s."tenant_id" = trash.tenant) and coalesce(better_supabase.can('tenant', trash.tenant, 'messages.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (trash.subject_id)::uuid and s."tenant_id" = trash.tenant) and coalesce(better_supabase.can('tenant', trash.tenant, 'deals.read'), false)
    when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (trash.subject_id)::uuid and s."tenant_id" = trash.tenant) and coalesce(better_supabase.can('tenant', trash.tenant, 'activities.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (trash.subject_id)::uuid and s."tenant_id" = trash.tenant) and coalesce(better_supabase.can('tenant', trash.tenant, 'tasks.read'), false)
    when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (trash.subject_id)::uuid and s."tenant_id" = trash.tenant) and coalesce(better_supabase.can('tenant', trash.tenant, 'risks.read'), false)
    when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (trash.subject_id)::uuid and s."tenant_id" = trash.tenant) and coalesce(better_supabase.can('tenant', trash.tenant, 'cases.read'), false)
    when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (trash.subject_id)::uuid and s."tenant_id" = trash.tenant) and coalesce(better_supabase.can('tenant', trash.tenant, 'inspections.read'), false)
    when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = (trash.subject_id)::uuid and s."tenant_id" = trash.tenant) and coalesce(better_supabase.can('tenant', trash.tenant, 'tax.read'), false)
    when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (trash.subject_id)::uuid and s."tenant_id" = trash.tenant) and coalesce(better_supabase.can('tenant', trash.tenant, 'manufacturing.read'), false)
    when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (trash.subject_id)::uuid and s."tenant_id" = trash.tenant) and coalesce(better_supabase.can('tenant', trash.tenant, 'banking.read'), false)
    when 'advisory_product' then exists (select 1 from "better_supabase"."advisory_products" s where s."id" = (trash.subject_id)::uuid and s."tenant_id" = trash.tenant) and coalesce(better_supabase.can('tenant', trash.tenant, 'advisories.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (trash.subject_id)::uuid and s."organization_id" = trash.tenant) and coalesce(better_supabase.can('tenant', trash.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (trash.subject_id)::uuid and s."tenant_id" = trash.tenant and (coalesce(better_supabase.can('tenant', trash.tenant, 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (trash.subject_id)::uuid and s."organization_id" = trash.tenant)
    else false
  end and case trash.subject_type
    when 'message' then coalesce(better_supabase.can('tenant', trash.tenant, 'messages.send'), false)
    when 'conversation' then coalesce(better_supabase.can('tenant', trash.tenant, 'messages.send'), false)
    when 'deal' then coalesce(better_supabase.can('tenant', trash.tenant, 'deals.write'), false)
    when 'activity' then coalesce(better_supabase.can('tenant', trash.tenant, 'activities.write'), false)
    when 'work_item' then coalesce(better_supabase.can('tenant', trash.tenant, 'tasks.write'), false)
    when 'risk' then coalesce(better_supabase.can('tenant', trash.tenant, 'risks.write'), false)
    when 'case' then coalesce(better_supabase.can('tenant', trash.tenant, 'cases.write'), false)
    when 'inspection_program' then coalesce(better_supabase.can('tenant', trash.tenant, 'inspections.manage'), false)
    when 'tax_code' then coalesce(better_supabase.can('tenant', trash.tenant, 'tax.manage'), false)
    when 'work_center' then coalesce(better_supabase.can('tenant', trash.tenant, 'manufacturing.manage'), false)
    when 'bank_account' then coalesce(better_supabase.can('tenant', trash.tenant, 'banking.manage'), false)
    when 'advisory_product' then coalesce(better_supabase.can('tenant', trash.tenant, 'advisories.write'), false)
    when 'customer' then coalesce(better_supabase.can('tenant', trash.tenant, 'customers.write'), false)
    when 'drive_node' then coalesce(better_supabase.can('tenant', trash.tenant, 'drive.manage'), false)
    else true
  end)) then
    raise exception 'not allowed to trash this record' using errcode = '42501', hint = 'TRASH_FORBIDDEN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_trash"(uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text)', v_hook::oid::regproc)
        using trash.tenant, trash.subject_type, trash.subject_id;
    end if;
  end;
  v_count := "better_supabase"."trash_cascade"(trash.tenant, trash.subject_type, trash.subject_id, v_batch, 0, auth.uid());
  if v_count = 0 then
    raise exception 'no live record to trash' using errcode = 'P0002', hint = 'TRASH_NOT_FOUND';
  end if;
  select i."id" into v_id from "better_supabase"."trash_items" i
    where i."subject_type" = trash.subject_type and i."subject_id" = trash.subject_id;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_trash"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using v_id, v_batch;
    end if;
  end;
  return jsonb_build_object('id', v_id, 'batchId', v_batch, 'count', v_count);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.trash_cascade (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  batch        uuid,
  depth        integer,
  actor        uuid
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_title text;
  v_count integer := 1;
  v_child text;
  v_item "better_supabase"."trash_items"%rowtype;
begin
  case trash_cascade.subject_type
    when 'message' then
      update "better_supabase"."messages" s set "archived_at" = now()
        where s."id" = (trash_cascade.subject_id)::uuid
          and s."tenant_id" = trash_cascade.tenant
          and s."archived_at" is null
        returning s."body"::text into v_title;
    when 'conversation' then
      update "better_supabase"."conversations" s set "archived_at" = now()
        where s."id" = (trash_cascade.subject_id)::uuid
          and s."tenant_id" = trash_cascade.tenant
          and s."archived_at" is null
        returning s."title"::text into v_title;
    when 'deal' then
      update "better_supabase"."deals" s set "archived_at" = now()
        where s."id" = (trash_cascade.subject_id)::uuid
          and s."tenant_id" = trash_cascade.tenant
          and s."archived_at" is null
        returning s."name"::text into v_title;
    when 'activity' then
      update "better_supabase"."activities" s set "archived_at" = now()
        where s."id" = (trash_cascade.subject_id)::uuid
          and s."tenant_id" = trash_cascade.tenant
          and s."archived_at" is null
        returning s."title"::text into v_title;
    when 'work_item' then
      update "better_supabase"."work_items" s set "archived_at" = now()
        where s."id" = (trash_cascade.subject_id)::uuid
          and s."tenant_id" = trash_cascade.tenant
          and s."archived_at" is null
        returning s."title"::text into v_title;
    when 'risk' then
      update "better_supabase"."risks" s set "archived_at" = now()
        where s."id" = (trash_cascade.subject_id)::uuid
          and s."tenant_id" = trash_cascade.tenant
          and s."archived_at" is null
        returning s."title"::text into v_title;
    when 'case' then
      update "better_supabase"."cases" s set "archived_at" = now()
        where s."id" = (trash_cascade.subject_id)::uuid
          and s."tenant_id" = trash_cascade.tenant
          and s."archived_at" is null
        returning s."title"::text into v_title;
    when 'inspection_program' then
      update "better_supabase"."inspection_programs" s set "archived_at" = now()
        where s."id" = (trash_cascade.subject_id)::uuid
          and s."tenant_id" = trash_cascade.tenant
          and s."archived_at" is null
        returning s."name"::text into v_title;
    when 'tax_code' then
      update "better_supabase"."tax_codes" s set "archived_at" = now()
        where s."id" = (trash_cascade.subject_id)::uuid
          and s."tenant_id" = trash_cascade.tenant
          and s."archived_at" is null
        returning s."name"::text into v_title;
    when 'work_center' then
      update "better_supabase"."work_centers" s set "archived_at" = now()
        where s."id" = (trash_cascade.subject_id)::uuid
          and s."tenant_id" = trash_cascade.tenant
          and s."archived_at" is null
        returning s."name"::text into v_title;
    when 'bank_account' then
      update "better_supabase"."bank_accounts" s set "archived_at" = now()
        where s."id" = (trash_cascade.subject_id)::uuid
          and s."tenant_id" = trash_cascade.tenant
          and s."archived_at" is null
        returning s."name"::text into v_title;
    when 'advisory_product' then
      update "better_supabase"."advisory_products" s set "archived_at" = now()
        where s."id" = (trash_cascade.subject_id)::uuid
          and s."tenant_id" = trash_cascade.tenant
          and s."archived_at" is null
        returning s."name"::text into v_title;
    when 'customer' then
      update "public"."customers" s set "archived_at" = now()
        where s."id" = (trash_cascade.subject_id)::uuid
          and s."organization_id" = trash_cascade.tenant
          and s."archived_at" is null
        returning s."name"::text into v_title;
    when 'drive_node' then
      update "better_supabase"."drive_nodes" s set "archived_at" = now()
        where s."id" = (trash_cascade.subject_id)::uuid
          and s."tenant_id" = trash_cascade.tenant
          and s."archived_at" is null
        returning s."name"::text into v_title;
    when 'project' then
      update "public"."projects" s set "deleted_at" = now()
        where s."id" = (trash_cascade.subject_id)::uuid
          and s."organization_id" = trash_cascade.tenant
          and s."deleted_at" is null
        returning s."name"::text into v_title;
    else
      raise exception 'this subject type has no deletedAt column' using errcode = '22023', hint = 'TRASH_UNSUPPORTED';
  end case;
  if not found then
    return 0;
  end if;
  delete from "better_supabase"."trash_items" i
    where i."subject_type" = trash_cascade.subject_type and i."subject_id" = trash_cascade.subject_id;
  insert into "better_supabase"."trash_items" ("tenant_id", "subject_type", "subject_id", "title", "batch_id", "depth", "trashed_by", "trashed_at", "purge_at")
  values (trash_cascade.tenant, trash_cascade.subject_type, trash_cascade.subject_id, v_title, trash_cascade.batch, trash_cascade.depth, trash_cascade.actor, now(), now() + make_interval(days => 30))
  returning * into v_item;
  perform "better_supabase".emit_event('subject.trashed', jsonb_build_object('organizationId', v_item."tenant_id", 'subjectType', v_item."subject_type", 'subjectId', v_item."subject_id", 'id', v_item."id", 'batchId', v_item."batch_id"), 'trash-items/' || v_item."id"::text, (v_item."tenant_id")::text, null, 'better-supabase/trash');
  perform better_supabase.audit_event(
    event_type => 'subject.trashed',
    category => 'data',
    target_type => 'trash_item',
    record_id => v_item."id"::text,
    summary => 'trashed' || ' ' || v_item."subject_type" || ' ' || v_item."subject_id",
    tenant => (v_item."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_item."tenant_id", 'subjectType', v_item."subject_type", 'subjectId', v_item."subject_id", 'id', v_item."id", 'batchId', v_item."batch_id")
  );
  
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.trash_purge_batch (
  batch uuid
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_item "better_supabase"."trash_items"%rowtype;
  v_count integer := 0;
begin
  for v_item in select * from "better_supabase"."trash_items" where "batch_id" = trash_purge_batch.batch order by "depth" desc loop
    if (false) then
      raise exception 'a record in this batch is under a legal hold' using errcode = '42501', hint = 'TRASH_HELD';
    end if;
    case v_item.subject_type
    when 'message' then
      delete from "better_supabase"."messages" s
        where s."id" = (v_item.subject_id)::uuid;
    when 'conversation' then
      delete from "better_supabase"."conversations" s
        where s."id" = (v_item.subject_id)::uuid;
    when 'deal' then
      delete from "better_supabase"."deals" s
        where s."id" = (v_item.subject_id)::uuid;
    when 'activity' then
      delete from "better_supabase"."activities" s
        where s."id" = (v_item.subject_id)::uuid;
    when 'work_item' then
      delete from "better_supabase"."work_items" s
        where s."id" = (v_item.subject_id)::uuid;
    when 'risk' then
      delete from "better_supabase"."risks" s
        where s."id" = (v_item.subject_id)::uuid;
    when 'case' then
      delete from "better_supabase"."cases" s
        where s."id" = (v_item.subject_id)::uuid;
    when 'inspection_program' then
      delete from "better_supabase"."inspection_programs" s
        where s."id" = (v_item.subject_id)::uuid;
    when 'tax_code' then
      delete from "better_supabase"."tax_codes" s
        where s."id" = (v_item.subject_id)::uuid;
    when 'work_center' then
      delete from "better_supabase"."work_centers" s
        where s."id" = (v_item.subject_id)::uuid;
    when 'bank_account' then
      delete from "better_supabase"."bank_accounts" s
        where s."id" = (v_item.subject_id)::uuid;
    when 'advisory_product' then
      delete from "better_supabase"."advisory_products" s
        where s."id" = (v_item.subject_id)::uuid;
    when 'customer' then
      delete from "public"."customers" s
        where s."id" = (v_item.subject_id)::uuid;
    when 'drive_node' then
      delete from "better_supabase"."drive_nodes" s
        where s."id" = (v_item.subject_id)::uuid;
    when 'project' then
      delete from "public"."projects" s
        where s."id" = (v_item.subject_id)::uuid;
    else null;
  end case;
    perform "better_supabase".emit_event('subject.purged', jsonb_build_object('organizationId', v_item."tenant_id", 'subjectType', v_item."subject_type", 'subjectId', v_item."subject_id", 'id', v_item."id", 'batchId', v_item."batch_id"), 'trash-items/' || v_item."id"::text, (v_item."tenant_id")::text, null, 'better-supabase/trash');
  perform better_supabase.audit_event(
    event_type => 'subject.purged',
    category => 'data',
    target_type => 'trash_item',
    record_id => v_item."id"::text,
    summary => 'purged' || ' ' || v_item."subject_type" || ' ' || v_item."subject_id",
    tenant => (v_item."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_item."tenant_id", 'subjectType', v_item."subject_type", 'subjectId', v_item."subject_id", 'id', v_item."id", 'batchId', v_item."batch_id")
  );
    v_count := v_count + 1;
  end loop;
  delete from "better_supabase"."trash_items" where "batch_id" = trash_purge_batch.batch;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.trash_restore_batch (
  batch uuid
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_item "better_supabase"."trash_items"%rowtype;
  v_count integer := 0;
begin
  for v_item in select * from "better_supabase"."trash_items" where "batch_id" = trash_restore_batch.batch order by "depth" loop
    case v_item.subject_type
    when 'message' then
      update "better_supabase"."messages" s set "archived_at" = null
        where s."id" = (v_item.subject_id)::uuid;
    when 'conversation' then
      update "better_supabase"."conversations" s set "archived_at" = null
        where s."id" = (v_item.subject_id)::uuid;
    when 'deal' then
      update "better_supabase"."deals" s set "archived_at" = null
        where s."id" = (v_item.subject_id)::uuid;
    when 'activity' then
      update "better_supabase"."activities" s set "archived_at" = null
        where s."id" = (v_item.subject_id)::uuid;
    when 'work_item' then
      update "better_supabase"."work_items" s set "archived_at" = null
        where s."id" = (v_item.subject_id)::uuid;
    when 'risk' then
      update "better_supabase"."risks" s set "archived_at" = null
        where s."id" = (v_item.subject_id)::uuid;
    when 'case' then
      update "better_supabase"."cases" s set "archived_at" = null
        where s."id" = (v_item.subject_id)::uuid;
    when 'inspection_program' then
      update "better_supabase"."inspection_programs" s set "archived_at" = null
        where s."id" = (v_item.subject_id)::uuid;
    when 'tax_code' then
      update "better_supabase"."tax_codes" s set "archived_at" = null
        where s."id" = (v_item.subject_id)::uuid;
    when 'work_center' then
      update "better_supabase"."work_centers" s set "archived_at" = null
        where s."id" = (v_item.subject_id)::uuid;
    when 'bank_account' then
      update "better_supabase"."bank_accounts" s set "archived_at" = null
        where s."id" = (v_item.subject_id)::uuid;
    when 'advisory_product' then
      update "better_supabase"."advisory_products" s set "archived_at" = null
        where s."id" = (v_item.subject_id)::uuid;
    when 'customer' then
      update "public"."customers" s set "archived_at" = null
        where s."id" = (v_item.subject_id)::uuid;
    when 'drive_node' then
      update "better_supabase"."drive_nodes" s set "archived_at" = null
        where s."id" = (v_item.subject_id)::uuid;
    when 'project' then
      update "public"."projects" s set "deleted_at" = null
        where s."id" = (v_item.subject_id)::uuid;
    else null;
  end case;
    perform "better_supabase".emit_event('subject.restored', jsonb_build_object('organizationId', v_item."tenant_id", 'subjectType', v_item."subject_type", 'subjectId', v_item."subject_id", 'id', v_item."id", 'batchId', v_item."batch_id"), 'trash-items/' || v_item."id"::text, (v_item."tenant_id")::text, null, 'better-supabase/trash');
  perform better_supabase.audit_event(
    event_type => 'subject.restored',
    category => 'data',
    target_type => 'trash_item',
    record_id => v_item."id"::text,
    summary => 'restored' || ' ' || v_item."subject_type" || ' ' || v_item."subject_id",
    tenant => (v_item."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_item."tenant_id", 'subjectType', v_item."subject_type", 'subjectId', v_item."subject_id", 'id', v_item."id", 'batchId', v_item."batch_id")
  );
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.unbilled_time (
  tenant   uuid,
  scope    jsonb DEFAULT NULL::jsonb,
  group_by text  DEFAULT 'subject'::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_scope jsonb := coalesce(unbilled_time.scope, '{}'::jsonb);
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', unbilled_time.tenant, 'billable_time.read'), false)) then
    raise exception 'not allowed to read billable time' using errcode = '42501', hint = 'BILLABLE_TIME_FORBIDDEN';
  end if;
  if unbilled_time.group_by not in ('subject', 'member', 'entry') then
    raise exception 'group_by is subject, member or entry' using errcode = '22023', hint = 'BILLABLE_TIME_GROUPING_INVALID';
  end if;
  return jsonb_build_object(
    'lines', (select coalesce(jsonb_agg(jsonb_build_object('description', l.description, 'quantity', l.quantity, 'unitAmount', l.rate::text, 'currency', l.currency, 'amount', round(l.quantity * l.rate)::bigint::text, 'entryIds', l.entry_ids, 'subjectType', l.subject_type, 'subjectId', l.subject_id, 'userId', coalesce(l.member_text, l.user_text)) order by l.currency, l.first_at), '[]'::jsonb)
      from (
    select min(u.started_at) as first_at, u.currency, u.rate,
      round(sum(u.seconds) / 3600.0, 4) as quantity,
      jsonb_agg(u.id order by u.started_at, u.id) as entry_ids,
      case when unbilled_time.group_by = 'entry' then min(u.user_id::text) end as user_text,
      case when unbilled_time.group_by = 'member' then min(u.user_id::text) end as member_text,
      min(u.subject_type) as subject_type, min(u.subject_id) as subject_id,
      case
        when unbilled_time.group_by = 'entry' then coalesce(min(u.note), 'Time on ' || to_char(min(u.started_at) at time zone 'UTC', 'YYYY-MM-DD'))
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
    where x."tenant_id" = unbilled_time.tenant
      and x."billable" and x."ended_at" is not null and x."archived_at" is null
      and not exists (select 1 from "better_supabase"."time_invoice_entries" d where d."entry_id" = x."id")
      and (v_scope -> 'subject' is null or (x."subject_type" = v_scope -> 'subject' ->> 'type' and x."subject_id" = v_scope -> 'subject' ->> 'id'))
      and (v_scope ->> 'userId' is null or x."user_id" = (v_scope ->> 'userId')::uuid)
      and (v_scope ->> 'starts' is null or x."started_at" >= (v_scope ->> 'starts')::timestamptz)
      and (v_scope ->> 'ends' is null or x."started_at" < (v_scope ->> 'ends')::timestamptz)
      and (v_scope -> 'entryIds' is null or x."id"::text in (select jsonb_array_elements_text(v_scope -> 'entryIds')))) u
    where u.rate is not null
    group by u.currency, u.rate, u.subject_type, u.subject_id,
      case when unbilled_time.group_by in ('member', 'entry') then u.user_id end,
      case when unbilled_time.group_by = 'entry' then u.id end
    having round(sum(u.seconds) / 3600.0, 4) > 0) l),
    'totals', (select coalesce(jsonb_agg(jsonb_build_object('amount', t.amount::text, 'currency', t.currency) order by t.currency), '[]'::jsonb)
      from (select l.currency, sum(round(l.quantity * l.rate))::bigint as amount
        from (
    select min(u.started_at) as first_at, u.currency, u.rate,
      round(sum(u.seconds) / 3600.0, 4) as quantity,
      jsonb_agg(u.id order by u.started_at, u.id) as entry_ids,
      case when unbilled_time.group_by = 'entry' then min(u.user_id::text) end as user_text,
      case when unbilled_time.group_by = 'member' then min(u.user_id::text) end as member_text,
      min(u.subject_type) as subject_type, min(u.subject_id) as subject_id,
      case
        when unbilled_time.group_by = 'entry' then coalesce(min(u.note), 'Time on ' || to_char(min(u.started_at) at time zone 'UTC', 'YYYY-MM-DD'))
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
    where x."tenant_id" = unbilled_time.tenant
      and x."billable" and x."ended_at" is not null and x."archived_at" is null
      and not exists (select 1 from "better_supabase"."time_invoice_entries" d where d."entry_id" = x."id")
      and (v_scope -> 'subject' is null or (x."subject_type" = v_scope -> 'subject' ->> 'type' and x."subject_id" = v_scope -> 'subject' ->> 'id'))
      and (v_scope ->> 'userId' is null or x."user_id" = (v_scope ->> 'userId')::uuid)
      and (v_scope ->> 'starts' is null or x."started_at" >= (v_scope ->> 'starts')::timestamptz)
      and (v_scope ->> 'ends' is null or x."started_at" < (v_scope ->> 'ends')::timestamptz)
      and (v_scope -> 'entryIds' is null or x."id"::text in (select jsonb_array_elements_text(v_scope -> 'entryIds')))) u
    where u.rate is not null
    group by u.currency, u.rate, u.subject_type, u.subject_id,
      case when unbilled_time.group_by in ('member', 'entry') then u.user_id end,
      case when unbilled_time.group_by = 'entry' then u.id end
    having round(sum(u.seconds) / 3600.0, 4) > 0) l group by l.currency) t),
    'unrated', (select coalesce(jsonb_agg(u.id order by u.started_at), '[]'::jsonb)
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
    where x."tenant_id" = unbilled_time.tenant
      and x."billable" and x."ended_at" is not null and x."archived_at" is null
      and not exists (select 1 from "better_supabase"."time_invoice_entries" d where d."entry_id" = x."id")
      and (v_scope -> 'subject' is null or (x."subject_type" = v_scope -> 'subject' ->> 'type' and x."subject_id" = v_scope -> 'subject' ->> 'id'))
      and (v_scope ->> 'userId' is null or x."user_id" = (v_scope ->> 'userId')::uuid)
      and (v_scope ->> 'starts' is null or x."started_at" >= (v_scope ->> 'starts')::timestamptz)
      and (v_scope ->> 'ends' is null or x."started_at" < (v_scope ->> 'ends')::timestamptz)
      and (v_scope -> 'entryIds' is null or x."id"::text in (select jsonb_array_elements_text(v_scope -> 'entryIds')))) u where u.rate is null)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_activity (
  activity uuid,
  attrs    jsonb,
  subjects jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid := update_activity.activity;
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
  select x."tenant_id", x."type", x."owner_id" into v_tenant, v_type, v_previous_owner
  from "better_supabase"."activities" x where x."id" = v_id and ((auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and x."archived_at" is null);
  if v_tenant is null then
    raise exception 'no such activity you can edit' using errcode = 'P0002', hint = 'ACTIVITY_NOT_FOUND';
  end if;
  if update_activity.attrs ? 'type' and not (update_activity.attrs ->> 'type' = any ('{call,email,meeting,note,task}'::text[])) then
    raise exception 'unknown activity type' using errcode = '22023', hint = 'ACTIVITY_TYPE_INVALID';
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
  if exists (select 1 from "better_supabase"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the activity is locked: add an addendum with amend_activity instead' using errcode = '55000', hint = 'ACTIVITY_LOCKED';
  end if;
  if exists (select 1 from "better_supabase"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and x."archived_at" is not null) then
    raise exception 'the activity is archived: restore it first' using errcode = '55000', hint = 'ACTIVITY_ARCHIVED';
  end if;
  update "better_supabase"."activities" x set
    "type" = coalesce(update_activity.attrs ->> 'type', x."type"),
    "title" = coalesce(nullif(trim(update_activity.attrs ->> 'title'), ''), x."title"),
    "body" = case when update_activity.attrs ? 'body' then update_activity.attrs ->> 'body' else x."body" end,
    "outcome" = case when update_activity.attrs ? 'outcome' then update_activity.attrs ->> 'outcome' else x."outcome" end,
    "external_ref" = case when update_activity.attrs ? 'externalRef' then update_activity.attrs ->> 'externalRef' else x."external_ref" end,
    "owner_id" = case when update_activity.attrs ? 'ownerId' then nullif(update_activity.attrs ->> 'ownerId', '')::uuid else x."owner_id" end,
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
  returning x."type", x."title", x."owner_id" into v_type, v_title, v_owner;
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
      when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'rfq' then exists (select 1 from "better_supabase"."rfqs" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'till' then exists (select 1 from "better_supabase"."tills" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'warranty_claim' then exists (select 1 from "better_supabase"."warranty_claims" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'meeting' then exists (select 1 from "better_supabase"."meetings" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'meeting_decision' then exists (select 1 from "better_supabase"."meeting_decisions" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'maintenance_plan' then exists (select 1 from "better_supabase"."maintenance_plans" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'dam_usage_right' then exists (select 1 from "better_supabase"."dam_usage_rights" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'lims_sample' then exists (select 1 from "better_supabase"."lims_samples" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'advisory' then exists (select 1 from "better_supabase"."advisories" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'advisory_product' then exists (select 1 from "better_supabase"."advisory_products" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'vulnerability' then exists (select 1 from "better_supabase"."vulnerabilities" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'organization' then exists (select 1 from "public"."organizations" s where s."id" = ((v_item ->> 'id'))::uuid and s."id"::text = v_tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      else false
    end and "better_supabase"."can_subject"((v_item ->> 'type'), (v_item ->> 'id'), 'read')) then
      raise exception 'a subject is unknown or not readable in this organization' using errcode = '42501', hint = 'ACTIVITY_SUBJECT_FORBIDDEN';
    end if;
  end loop;
  delete from "better_supabase"."activity_subjects" x where x."activity_id" = v_id;
  insert into "better_supabase"."activity_subjects" ("tenant_id", "activity_id", "subject_type", "subject_id", "position")
  select v_tenant, v_id, s.value ->> 'type', s.value ->> 'id', s.ordinality::integer
  from jsonb_array_elements(coalesce(update_activity.subjects, '[]')) with ordinality s
  on conflict do nothing;
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."activity_subjects" sx where sx."activity_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  else
    v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."activity_subjects" sx where sx."activity_id" = v_id), '[]'::jsonb);
    v_first := v_subjects -> 0;
  end if;
  perform "better_supabase".emit_event('activity.updated', jsonb_build_object('organizationId', v_tenant, 'activityId', v_id, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects), 'activities/' || v_id::text, (v_tenant::text)::text, null, 'better-supabase/activities');
  if v_owner is not null and v_owner is distinct from auth.uid() and v_owner is distinct from v_previous_owner then
    if better_supabase.import_run() is null then
      v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'activity.assigned',
      'tenant', v_tenant,
      'actor', auth.uid(),
      'subject_type', v_first ->> 'type',
      'subject_id', v_first ->> 'id',
      'summary', v_title,
      'recipients', jsonb_build_array(v_owner),
      'watchers', false,
      'key', 'activity.assigned:' || v_id::text || ':' || v_owner::text,
      'data', jsonb_build_object('activityId', v_id)
    ));
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
  end if;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."activity_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."activities" x where x."id" = v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_time_entry (
  entry_id uuid,
  patch    jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."time_entries"%rowtype;
  v_patch jsonb := coalesce(update_time_entry.patch, '{}'::jsonb);
  v_previous_started_at timestamptz;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."time_entries" x where x."id" = update_time_entry.entry_id for update;
  if not found then
    raise exception 'time entry not found' using errcode = 'P0002', hint = 'TIME_ENTRY_NOT_FOUND';
  end if;
  v_previous_started_at := v_row."started_at";
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(v_row."user_id" = auth.uid(), false) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'time_entries.track'), false)) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'time_entries.manage'), false)) then
    raise exception 'not allowed to change this entry' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if v_patch ? 'startedAt' then
    v_row."started_at" := (v_patch ->> 'startedAt')::timestamptz;
  end if;
  if v_patch ? 'endedAt' then
    if v_patch ->> 'endedAt' is null then
      raise exception 'a finished entry can''t be restarted; start a timer instead' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
    end if;
    v_row."ended_at" := (v_patch ->> 'endedAt')::timestamptz;
  end if;
  if v_row."started_at" is null or (v_row."ended_at" is not null and v_row."ended_at" <= v_row."started_at") then
    raise exception 'ended_at must be after started_at' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
  end if;
  if v_patch ? 'subjectType' or v_patch ? 'subjectId' then
    v_row."subject_type" := v_patch ->> 'subjectType';
    v_row."subject_id" := v_patch ->> 'subjectId';
    if (v_row."subject_type" is null) <> (v_row."subject_id" is null) then
    raise exception 'name both subject_type and subject_id, or neither' using errcode = '22023', hint = 'TIME_SUBJECT_INVALID';
  end if;
  if v_row."subject_type" is not null and v_row."subject_type" <> all (array['company', 'project']::text[]) then
    raise exception 'time is tracked on company, project records' using errcode = '22023', hint = 'TIME_SUBJECT_INVALID';
  end if;
  if v_row."subject_type" is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case v_row."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'contacts.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'contacts.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'posts.read'), false)
    when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'activities.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'tasks.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'ledger.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'invoices.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'catalog.read'), false)
    when 'rfq' then exists (select 1 from "better_supabase"."rfqs" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'rfqs.read'), false)
    when 'till' then exists (select 1 from "better_supabase"."tills" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'tills.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'donations.read'), false)
    when 'warranty_claim' then exists (select 1 from "better_supabase"."warranty_claims" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'warranty.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'compliance.read'), false)
    when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'compliance.read'), false)
    when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'qualifications.read'), false)
    when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'risks.read'), false)
    when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.read'), false)
    when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.read'), false)
    when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.read'), false)
    when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'forms.read'), false)
    when 'meeting' then exists (select 1 from "better_supabase"."meetings" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.read'), false)
    when 'meeting_decision' then exists (select 1 from "better_supabase"."meeting_decisions" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.read'), false)
    when 'maintenance_plan' then exists (select 1 from "better_supabase"."maintenance_plans" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'maintenance.read'), false)
    when 'dam_usage_right' then exists (select 1 from "better_supabase"."dam_usage_rights" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'dam.read'), false)
    when 'lims_sample' then exists (select 1 from "better_supabase"."lims_samples" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'lims.read'), false)
    when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'tax.read'), false)
    when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'manufacturing.read'), false)
    when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'manufacturing.read'), false)
    when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'banking.read'), false)
    when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'care_plans.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'incidents.read'), false)
    when 'advisory' then exists (select 1 from "better_supabase"."advisories" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'advisories.read'), false)
    when 'advisory_product' then exists (select 1 from "better_supabase"."advisory_products" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'advisories.read'), false)
    when 'vulnerability' then exists (select 1 from "better_supabase"."vulnerabilities" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'advisories.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'content.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_row."subject_id")::uuid and s."organization_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id" and (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'organization' then exists (select 1 from "public"."organizations" s where s."id" = (v_row."subject_id")::uuid and s."id" = v_row."tenant_id")
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (v_row."subject_id")::uuid and s."organization_id" = v_row."tenant_id")
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_row."subject_id")::uuid and s."organization_id" = v_row."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_row."subject_id")::uuid and s."organization_id" = v_row."tenant_id")
    else false
  end) then
    raise exception 'not allowed to track time on this record' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  end if;
  if v_patch ? 'billable' then
    v_row."billable" := coalesce((v_patch ->> 'billable')::boolean, false);
  end if;
  if v_patch ? 'rate' or v_patch ? 'rateCurrency' then
    v_row."rate" := (v_patch ->> 'rate')::bigint;
    v_row."rate_currency" := v_patch ->> 'rateCurrency';
    if v_row."rate" is not null and v_row."rate_currency" is null then
    raise exception 'a rate needs rate_currency' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  if v_row."rate_currency" !~ '^[A-Z]{3}$' then
    raise exception 'rate_currency must be a three-letter currency code' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  end if;
  if v_patch ? 'note' then
    v_row."note" := v_patch ->> 'note';
  end if;
  if exists (
    select 1 from "better_supabase"."time_entries" x
    where x."tenant_id" = v_row."tenant_id" and x."user_id" = v_row."user_id" and x."id" <> v_row."id"
      and x."archived_at" is null
      and tstzrange(x."started_at", coalesce(x."ended_at", 'infinity'::timestamptz)) && tstzrange(v_row."started_at", coalesce(v_row."ended_at", 'infinity'::timestamptz))
  ) then
    raise exception 'this time overlaps another entry' using errcode = '23P01', hint = 'TIME_ENTRY_OVERLAP';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_time_entry_save"(uuid, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::uuid)', v_hook::oid::regproc)
        using v_row."id", v_row."tenant_id", v_row."user_id";
    end if;
  end;
  update "better_supabase"."time_entries" x
  set "started_at" = v_row."started_at",
      "ended_at" = v_row."ended_at",
      "subject_type" = v_row."subject_type",
      "subject_id" = v_row."subject_id",
      "billable" = v_row."billable",
      "rate" = v_row."rate",
      "rate_currency" = v_row."rate_currency",
      "note" = v_row."note",
      "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('time_entry.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'id', v_row."id", 'userId', v_row."user_id", 'startedAt', v_row."started_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency", 'previousStartedAt', v_previous_started_at), 'time-entries/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/time-entries');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_time_entry_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.wip_valuation (
  tenant uuid,
  as_of  date DEFAULT NULL::date
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_as_of date := coalesce(wip_valuation.as_of, current_date);
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', wip_valuation.tenant, 'billable_time.read'), false)) then
    raise exception 'not allowed to read billable time' using errcode = '42501', hint = 'BILLABLE_TIME_FORBIDDEN';
  end if;
  return (
    with open as (
      select extract(epoch from x."ended_at" - x."started_at") as seconds,
        card.cost, card.currency as cost_currency,
        coalesce(x."rate", card.rate) as rate, coalesce(x."rate_currency", card.currency) as rate_currency
      from "better_supabase"."time_entries" x
      left join lateral (
        select c."cost_amount" as cost, c."rate" as rate, c."currency"::text as currency
        from "better_supabase"."time_rates" c
        where c."tenant_id" = x."tenant_id"
          and (c."user_id" is null or c."user_id" = x."user_id")
          and (c."subject_type" is null or (c."subject_type" = x."subject_type" and c."subject_id" = x."subject_id"))
          and c."effective_from" <= (x."started_at" at time zone 'UTC')::date
        order by (c."subject_type" is not null) desc, (c."user_id" is not null) desc, c."effective_from" desc
        limit 1
      ) card on true
      where x."tenant_id" = wip_valuation.tenant
        and x."billable" and x."ended_at" is not null and x."archived_at" is null
        and (x."started_at" at time zone 'UTC')::date <= v_as_of
        and not exists (select 1 from "better_supabase"."time_invoice_entries" d where d."entry_id" = x."id")
    ),
    amounts as (
      select o.cost_currency as currency, round(o.seconds / 3600.0 * o.cost)::bigint as cost, 0::bigint as billable
      from open o where o.cost is not null
      union all
      select o.rate_currency, 0, round(o.seconds / 3600.0 * o.rate)::bigint
      from open o where o.rate is not null
    )
    select jsonb_build_object(
      'asOf', v_as_of,
      'hours', (select round(coalesce(sum(o.seconds), 0) / 3600.0, 2) from open o),
      'uncostedHours', (select round(coalesce(sum(o.seconds) filter (where o.cost is null), 0) / 3600.0, 2) from open o),
      'unratedHours', (select round(coalesce(sum(o.seconds) filter (where o.rate is null), 0) / 3600.0, 2) from open o),
      'totals', (select coalesce(jsonb_agg(jsonb_build_object('currency', t.currency, 'cost', t.cost::text, 'billable', t.billable::text) order by t.currency), '[]'::jsonb)
        from (select a.currency, sum(a.cost)::bigint as cost, sum(a.billable)::bigint as billable from amounts a group by a.currency) t)
    )
  );
end;
$function$;

CREATE TRIGGER bsb_search_activity_index
  AFTER INSERT OR DELETE OR UPDATE OF id, tenant_id, title, body, outcome, archived_at ON better_supabase.activities
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('activity', 'id');

REVOKE ALL ON FUNCTION "api"."activities_of"(text, text, text[], timestamp WITH time zone, integer, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."activities_of"(text, text, text[], timestamp WITH time zone, integer, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."archive_activity"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."archive_activity"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."archive_time_entry"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."archive_time_entry"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_time_entries"(uuid, uuid, timestamp WITH time zone, timestamp WITH time zone, text, text, boolean, integer, boolean) FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION "api"."list_time_entries"(uuid, uuid, timestamp WITH time zone, timestamp WITH time zone, text, text, boolean, integer, boolean)
  TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."purge_activity"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."purge_activity"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."purge_time_entry"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."purge_time_entry"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."restore_activity"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."restore_activity"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."restore_time_entry"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."restore_time_entry"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."activities_of"(text, text, text[], timestamp WITH time zone, integer, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."activities_of"(text, text, text[], timestamp WITH time zone, integer, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."archive_activity"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."archive_activity"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."archive_time_entry"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."archive_time_entry"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_time_entries"(uuid, uuid, timestamp WITH time zone, timestamp WITH time zone, text, text, boolean, integer, boolean) FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION "better_supabase"."list_time_entries"(uuid, uuid, timestamp WITH time zone, timestamp WITH time zone, text, text, boolean, integer, boolean)
  TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."purge_activity"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."purge_activity"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."purge_time_entry"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."purge_time_entry"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."restore_activity"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."restore_activity"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."restore_time_entry"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."restore_time_entry"(uuid) TO "authenticated", "service_role";
