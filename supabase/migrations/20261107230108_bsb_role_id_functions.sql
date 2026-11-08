SET local check_function_bodies = off;

ALTER TABLE "better_supabase"."ai_chat_participants"
  DROP CONSTRAINT "ai_chat_participants_customer_user_id_fkey";

ALTER TABLE "better_supabase"."application_scorecards"
  DROP CONSTRAINT "application_scorecards_application_id_stage_id_reviewer_use_key";

ALTER TABLE "better_supabase"."appraisals"
  DROP CONSTRAINT "appraisals_cycle_id_subject_user_id_key";

ALTER TABLE "better_supabase"."enrollment_steps"
  DROP CONSTRAINT "enrollment_steps_assignee_user_id_fkey";

ALTER TABLE "better_supabase"."passes"
  DROP CONSTRAINT "passes_holder_user_id_fkey";

DROP FUNCTION "api"."request_shift_swap"(uuid, uuid, text);

DROP FUNCTION "better_supabase"."request_shift_swap"(uuid, uuid, text);

CREATE OR REPLACE FUNCTION api.request_shift_swap (
  assignment_id uuid,
  to_id         uuid,
  note          text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."request_shift_swap"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION better_supabase.activity_transcript (
  recording uuid,
  after     integer,
  page_size integer
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(p.value order by p.position), '[]'::jsonb)
  from (
    select jsonb_build_object('position', sx."position", 'speaker', sx."speaker", 'speakerUserId', sx."speaker_id", 'startMs', sx."starts_ms", 'endMs', sx."ends_ms", 'text', sx."text", 'confidence', sx."confidence") as value, sx."position" as position
    from "better_supabase"."engagement_transcript_segments" sx
    where sx."recording_id" = activity_transcript.recording
      and sx."position" > coalesce(activity_transcript.after, 0)
    order by sx."position"
    limit least(greatest(coalesce(activity_transcript.page_size, 500), 1), 5000)
  ) p
$function$;

CREATE OR REPLACE FUNCTION better_supabase.activity_with_transcripts (
  engagement uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'engagement', to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()),
    'segments', coalesce((
      select jsonb_agg(jsonb_build_object('position', sx."position", 'speaker', sx."speaker", 'speakerUserId', sx."speaker_id", 'startMs', sx."starts_ms", 'endMs', sx."ends_ms", 'text', sx."text", 'confidence', sx."confidence") || jsonb_build_object('recordingId', rx."id") order by rx."created_at", rx."id", sx."position")
      from "better_supabase"."engagement_recordings" rx
      join "better_supabase"."engagement_transcript_segments" sx on sx."recording_id" = rx."id"
      where rx."activity_id" = x."id"
    ), '[]'::jsonb)
  )
  from "better_supabase"."activities" x
  where x."id" = activity_with_transcripts.engagement
$function$;

CREATE OR REPLACE FUNCTION better_supabase.add_ai_chat_participant (
  chat             uuid,
  participant      uuid,
  participant_role text  DEFAULT 'viewer'::text,
  fields           jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_chat record;
  v_role text := coalesce(add_ai_chat_participant.participant_role, 'viewer');
  v_row "better_supabase"."ai_chat_participants";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."id" as id, x."owner_id" as owner, x."organization_id" as tenant into v_chat
  from "better_supabase"."ai_chats" x where x."id" = add_ai_chat_participant.chat for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_chat.owner = (select auth.uid()), false)) then
    raise exception 'No chat %', add_ai_chat_participant.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and not coalesce(better_supabase.can('tenant', v_chat.tenant, 'ai_chat.share'), false) then
    raise exception 'You may not share chats here' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  if v_role not in ('viewer', 'editor') then
    raise exception 'A participant is a viewer or an editor, not %', v_role using errcode = '22023', hint = 'AI_CHAT_INVALID';
  end if;
  if add_ai_chat_participant.participant is null or add_ai_chat_participant.participant = v_chat.owner then
    raise exception 'The owner already takes part in chat %', add_ai_chat_participant.chat using errcode = '22023', hint = 'AI_CHAT_INVALID';
  end if;
  if v_chat.tenant is not null and not coalesce(better_supabase.can_user(add_ai_chat_participant.participant, 'tenant', v_chat.tenant, 'ai_chat.read'), false) then
    raise exception '% can''t read chats in the chat''s organization', add_ai_chat_participant.participant using errcode = '22023', hint = 'AI_CHAT_INVALID';
  end if;
  insert into "better_supabase"."ai_chat_participants" ("chat_id", "user_id", "kind", "role", "added_by")
  values (v_chat.id, add_ai_chat_participant.participant, 'user', v_role, auth.uid())
  on conflict ("chat_id", "user_id") where "kind" = 'user' do update set "role" = excluded."role"
  returning * into v_row;
  update "better_supabase"."ai_chats" c set "visibility" = 'shared', "updated_at" = now()
  where c."id" = v_chat.id and c."visibility" = 'private';
  perform "better_supabase"."ai_chat_notify"(v_chat.id, add_ai_chat_participant.participant, 'participant.added', jsonb_build_object('userId', add_ai_chat_participant.participant, 'role', v_role), true);
  return jsonb_build_object('id', v_row."id", 'chat_id', v_row."chat_id", 'user_id', v_row."user_id", 'kind', v_row."kind", 'team_id', v_row."team_id", 'customer_id', v_row."customer_id", 'email', v_row."email", 'role', v_row."role", 'added_by', v_row."added_by", 'created_at', v_row."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.add_ai_chat_party (
  chat             uuid,
  party_kind       text,
  party            text,
  participant_role text DEFAULT 'viewer'::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_chat record;
  v_role text := coalesce(add_ai_chat_party.participant_role, 'viewer');
  v_team uuid;
  v_row "better_supabase"."ai_chat_participants";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."id" as id, x."owner_id" as owner, x."organization_id" as tenant into v_chat
  from "better_supabase"."ai_chats" x where x."id" = add_ai_chat_party.chat for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_chat.owner = (select auth.uid()), false)) then
    raise exception 'No chat %', add_ai_chat_party.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and not coalesce(better_supabase.can('tenant', v_chat.tenant, 'ai_chat.share'), false) then
    raise exception 'You may not share chats here' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  if v_role not in ('viewer', 'editor') then
    raise exception 'A participant is a viewer or an editor, not %', v_role using errcode = '22023', hint = 'AI_CHAT_INVALID';
  end if;
  if add_ai_chat_party.party_kind not in ('team', 'customer', 'external') or add_ai_chat_party.party is null then
    raise exception 'A party is a team, a customer or an external email, not %', add_ai_chat_party.party_kind using errcode = '22023', hint = 'AI_CHAT_INVALID';
  end if;
  if add_ai_chat_party.party_kind = 'team' then
    v_team := add_ai_chat_party.party::uuid;
    if v_chat.tenant is null then
      raise exception 'A chat outside an organization has no teams' using errcode = '22023', hint = 'AI_CHAT_INVALID';
    end if;
  elsif add_ai_chat_party.party_kind = 'customer' then
    if v_chat.tenant is null then
      raise exception 'A customer needs a chat in an organization' using errcode = '22023', hint = 'AI_CHAT_INVALID';
    end if;
    if add_ai_chat_party.party::uuid = v_chat.owner then
      raise exception 'The owner already takes part in chat %', add_ai_chat_party.chat using errcode = '22023', hint = 'AI_CHAT_INVALID';
    end if;
  elsif add_ai_chat_party.party !~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception '% is not an email address', add_ai_chat_party.party using errcode = '22023', hint = 'AI_CHAT_INVALID';
  end if;
  if add_ai_chat_party.party_kind = 'team' then
    insert into "better_supabase"."ai_chat_participants" ("chat_id", "kind", "team_id", "role", "added_by")
    values (v_chat.id, 'team', add_ai_chat_party.party::uuid, v_role, auth.uid())
    on conflict ("chat_id", "team_id") where "kind" = 'team' do update set "role" = excluded."role"
    returning * into v_row;
  elsif add_ai_chat_party.party_kind = 'customer' then
    insert into "better_supabase"."ai_chat_participants" ("chat_id", "kind", "customer_id", "role", "added_by")
    values (v_chat.id, 'customer', add_ai_chat_party.party::uuid, v_role, auth.uid())
    on conflict ("chat_id", "customer_id") where "kind" = 'customer' do update set "role" = excluded."role"
    returning * into v_row;
  elsif add_ai_chat_party.party_kind = 'external' then
    insert into "better_supabase"."ai_chat_participants" ("chat_id", "kind", "email", "role", "added_by")
    values (v_chat.id, 'external', lower(btrim(add_ai_chat_party.party)), v_role, auth.uid())
    on conflict ("chat_id", lower("email")) where "kind" = 'external' do update set "role" = excluded."role"
    returning * into v_row;
  end if;
  update "better_supabase"."ai_chats" c set "visibility" = 'shared', "updated_at" = now()
  where c."id" = v_chat.id and c."visibility" = 'private';
  perform "better_supabase"."ai_chat_notify"(v_chat.id, v_chat.owner, 'participant.added', jsonb_build_object('kind', add_ai_chat_party.party_kind, 'role', v_role), true);
  return jsonb_build_object('id', v_row."id", 'chat_id', v_row."chat_id", 'user_id', v_row."user_id", 'kind', v_row."kind", 'team_id', v_row."team_id", 'customer_id', v_row."customer_id", 'email', v_row."email", 'role', v_row."role", 'added_by', v_row."added_by", 'created_at', v_row."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.ai_chat_can_read (
  chat uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select exists (
    select 1 from "better_supabase"."ai_chats" x
    where x."id" = ai_chat_can_read.chat
      and (
        coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
        or x."owner_id" = (select auth.uid())
        or (x."visibility" = 'organization' and coalesce(better_supabase.can('tenant', x."organization_id", 'ai_chat.read'), false))
        or (x."visibility" <> 'private' and exists (select 1 from "better_supabase"."ai_chat_participants" pa where pa."chat_id" = x."id" and ((((pa."kind"::text = 'user' and pa."user_id" = (select auth.uid())) or (pa."kind"::text = 'team' and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = pa."team_id"::text and tm."user_id" = (select auth.uid())))) and (x."organization_id" is null or x."organization_id" in (select better_supabase.member_organization_ids()))) or (pa."kind"::text = 'customer' and pa."customer_id" = (select auth.uid()) and ((x."organization_id")::text, ('ai-chat')::text, (x."id"::text)::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g)))))
      )
  );
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
  where x."id" = amend_activity.engagement and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or x."tenant_id" in (select better_supabase.tenant_ids_with('activities.read')) and (
  not exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."activity_id" = x."id")
  or exists (select 1 from "better_supabase"."engagement_subjects" lx where lx."activity_id" = x."id" and "better_supabase"."can_subject"(lx."subject_type", lx."subject_id", 'read'))
) and (x."audience" <> 'restricted' or x."tenant_id" in (select better_supabase.tenant_ids_with('activities.read_restricted')) or x."owner_id" = (select auth.uid()) or x."created_by" = (select auth.uid()) or exists (select 1 from "better_supabase"."engagement_subjects" nx where nx."activity_id" = x."id" and "better_supabase"."has_subject_role"(nx."subject_type", nx."subject_id", x."restricted_roles"))));
  if v_from."id" is null then
    raise exception 'no such engagement you can read' using errcode = 'P0002', hint = 'ACTIVITY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_from."tenant_id", 'activities.write'), false)) then
    raise exception 'not allowed to amend engagements' using errcode = '42501', hint = 'ACTIVITY_FORBIDDEN';
  end if;
  if v_body is null then
    raise exception 'an addendum needs a body' using errcode = '23502', hint = 'ACTIVITY_BODY_REQUIRED';
  end if;
  insert into "better_supabase"."activities" ("tenant_id", "type", "title", "body", "owner_id", "amends_id", "audience", "restricted_roles", "category", "goal_id", "locked_at", "created_by")
  values (v_from."tenant_id", v_from."type", v_from."title", v_body, auth.uid(), v_from."id", v_from."audience", v_from."restricted_roles", v_from."category", v_from."goal_id", case when v_from."type"::text = any ('{note,report}'::text[]) then now() + interval '24 hours' end, auth.uid())
  returning "id" into v_id;
  insert into "better_supabase"."engagement_subjects" ("tenant_id", "activity_id", "subject_type", "subject_id", "position")
  select k."tenant_id", v_id, k."subject_type", k."subject_id", k."position"
  from "better_supabase"."engagement_subjects" k where k."activity_id" = v_from."id";
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  perform "better_supabase".emit_event('activity.amended', jsonb_build_object('organizationId', v_from."tenant_id", 'engagementId', v_id, 'type', v_from."type"::text, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects, 'amendsId', v_from."id"), 'engagements/' || v_id::text, (v_from."tenant_id"::text)::text, null, 'better-supabase/activities');
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."activities" x where x."id" = v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.append_ai_user_message (
  chat       uuid,
  message    jsonb,
  trigger    text  DEFAULT 'submit-message'::text,
  message_id text  DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_chat "better_supabase"."ai_chats";
  v_existing "better_supabase"."ai_messages";
  v_id text;
  v_parent text;
  v_target text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_chat from "better_supabase"."ai_chats" x where x."id" = append_ai_user_message.chat for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_chat."owner_id" = (select auth.uid()), false) or (v_chat."visibility" <> 'private' and exists (select 1 from "better_supabase"."ai_chat_participants" pa where pa."chat_id" = v_chat."id" and pa."role"::text in ('editor') and ((((pa."kind"::text = 'user' and pa."user_id" = (select auth.uid())) or (pa."kind"::text = 'team' and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = pa."team_id"::text and tm."user_id" = (select auth.uid())))) and (v_chat."organization_id" is null or v_chat."organization_id" in (select better_supabase.member_organization_ids()))) or (pa."kind"::text = 'customer' and pa."customer_id" = (select auth.uid()) and ((v_chat."organization_id")::text, ('ai-chat')::text, (v_chat."id"::text)::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g)))))) then
    raise exception 'No chat %', append_ai_user_message.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  if coalesce(append_ai_user_message.trigger, 'submit-message') = 'regenerate-message' then
    v_target := coalesce(append_ai_user_message.message_id, v_chat."current_leaf_id");
    select * into v_existing from "better_supabase"."ai_messages" x where x."chat_id" = v_chat."id" and x."id" = v_target;
    if not found then
      raise exception 'No message % to regenerate', v_target using errcode = 'P0002', hint = 'AI_MESSAGE_NOT_FOUND';
    end if;
    v_parent := case when v_existing."role" = 'user' then v_existing."id" else v_existing."parent_id" end;
    update "better_supabase"."ai_chats" x set "current_leaf_id" = v_parent, "updated_at" = now() where x."id" = v_chat."id";
    perform "better_supabase"."ai_chat_notify"(v_chat."id", null, 'leaf.changed', jsonb_build_object('leafId', v_parent), false);
    return jsonb_build_object('message_id', v_parent, 'parent_id', v_parent, 'created', false);
  elsif append_ai_user_message.trigger <> 'submit-message' then
    raise exception 'Unknown trigger %', append_ai_user_message.trigger using errcode = '22023', hint = 'AI_MESSAGE_INVALID';
  end if;
  if jsonb_typeof(append_ai_user_message.message) is distinct from 'object'
    or append_ai_user_message.message ->> 'role' is distinct from 'user'
    or nullif(append_ai_user_message.message ->> 'id', '') is null
    or jsonb_typeof(append_ai_user_message.message -> 'parts') is distinct from 'array' then
    raise exception 'A user message needs an id, role user and parts' using errcode = '22023', hint = 'AI_MESSAGE_INVALID';
  end if;
  v_id := append_ai_user_message.message ->> 'id';
  select * into v_existing from "better_supabase"."ai_messages" x where x."chat_id" = v_chat."id" and x."id" = v_id;
  if found then
    if v_existing."parts" = append_ai_user_message.message -> 'parts' then
      return jsonb_build_object('message_id', v_id, 'parent_id', v_existing."parent_id", 'created', false);
    end if;
    v_parent := v_existing."parent_id";
    v_id := gen_random_uuid()::text;
  elsif append_ai_user_message.message_id is not null then
    select x."parent_id" into v_parent from "better_supabase"."ai_messages" x
    where x."chat_id" = v_chat."id" and x."id" = append_ai_user_message.message_id;
    if not found then
      raise exception 'No message %', append_ai_user_message.message_id using errcode = 'P0002', hint = 'AI_MESSAGE_NOT_FOUND';
    end if;
  else
    v_parent := v_chat."current_leaf_id";
  end if;
  insert into "better_supabase"."ai_messages" ("chat_id", "id", "parent_id", "owner_id", "author_id", "role", "parts", "metadata")
  values (
    v_chat."id", v_id, v_parent, v_chat."owner_id", auth.uid(), 'user', append_ai_user_message.message -> 'parts',
    case when jsonb_typeof(append_ai_user_message.message -> 'metadata') = 'object' then append_ai_user_message.message -> 'metadata' else '{}'::jsonb end
  );
  update "better_supabase"."ai_chats" x set "current_leaf_id" = v_id, "last_message_at" = clock_timestamp(), "updated_at" = now() where x."id" = v_chat."id";
  perform "better_supabase"."ai_chat_notify"(v_chat."id", v_chat."owner_id", 'message.saved', jsonb_build_object('messageId', v_id), not v_chat."is_temporary");
  return jsonb_build_object('message_id', v_id, 'parent_id', v_parent, 'created', true);
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
    raise exception 'no such job you can add applications to' using errcode = 'P0002', hint = 'JOB_OPENING_NOT_FOUND';
  end if;
  if v_job."status" <> 'open' then
    raise exception 'the job isn''t open' using errcode = '55000', hint = 'JOB_OPENING_NOT_OPEN';
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
      when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'rfq' then exists (select 1 from "better_supabase"."rfqs" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'till' then exists (select 1 from "better_supabase"."tills" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'meeting' then exists (select 1 from "better_supabase"."meetings" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'meeting_decision' then exists (select 1 from "better_supabase"."meeting_decisions" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'maintenance_plan' then exists (select 1 from "better_supabase"."maintenance_plans" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'dam_usage_right' then exists (select 1 from "better_supabase"."dam_usage_rights" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'lims_sample' then exists (select 1 from "better_supabase"."lims_samples" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_id)::uuid and s."organization_id"::text = v_job."tenant_id"::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (v_id)::uuid and s."organization_id"::text = v_job."tenant_id"::text)
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
  insert into "better_supabase"."applications" ("tenant_id", "job_id", "candidate_type", "candidate_id", "source", "owner_id")
  values (v_job."tenant_id", v_job."id", v_type, v_id, nullif(trim(apply_to_job.source), ''), coalesce(apply_to_job.owner, auth.uid()))
  returning * into v_row;
  perform "better_supabase".emit_event('application.created', jsonb_build_object('organizationId', v_row."tenant_id", 'applicationId', v_row."id", 'subjectType', 'application', 'subjectId', v_row."id"::text, 'jobId', v_row."job_id", 'candidateType', v_row."candidate_type", 'candidateId', v_row."candidate_id"), 'applications/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/hiring');
  return to_jsonb(v_row);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.appraisal_approved (
  appraisal_id uuid
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."appraisals";
begin
  select * into v_row from "better_supabase"."appraisals" x
  where x."id" = appraisal_approved.appraisal_id and x."status" = 'awaiting_signoff' for update;
  if not found then
    return;
  end if;
  update "better_supabase"."appraisals" x
  set "status" = 'signed_off', "signed_off_at" = now(), "signed_off_by" = auth.uid(), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('appraisal.finalized', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'cycleId', v_row."cycle_id", 'subjectUserId', v_row."appraisee_id", 'status', v_row."status", 'rating', coalesce(v_row."calibrated_rating"::numeric, v_row."rating")), 'appraisals/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/appraisals');
  perform better_supabase.audit_event(
    event_type => 'appraisal.finalized',
    category => 'data',
    target_type => 'appraisal',
    record_id => v_row."id"::text,
    summary => 'appraisal signed off',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'cycleId', v_row."cycle_id", 'subjectUserId', v_row."appraisee_id", 'status', v_row."status", 'rating', coalesce(v_row."calibrated_rating"::numeric, v_row."rating"))
  );
  perform "better_supabase"."appraisal_step"(v_row."id", 'sign_off');
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.appraisal_json (
  appraisal_id uuid,
  all_reviews  boolean
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'cycleId', x."cycle_id",
    'subjectUserId', x."appraisee_id", 'managerId', x."manager_id", 'status', x."status",
    'rating', x."rating"::text, 'calibratedRating', x."calibrated_rating", 'approvalId', x."approval_id",
    'signedOffAt', x."signed_off_at", 'signedOffBy', x."signed_off_by", 'createdAt', x."created_at",
    'rubric', coalesce((
      select jsonb_agg(jsonb_build_object('key', w."key", 'name', w."name", 'weight', w."weight") order by w."position")
      from "better_supabase"."appraisal_competencies" w where w."cycle_id" = x."cycle_id"
    ), '[]'::jsonb),
    'competencies', case when appraisal_json.all_reviews or (x."appraisee_id" = auth.uid() and x."status" = 'signed_off'
      and (select z."share_feedback" from "better_supabase"."appraisal_cycles" z where z."id" = x."cycle_id")) then coalesce((
      select jsonb_agg(jsonb_build_object('key', w."key", 'name', w."name", 'weight', w."weight",
        'average', (
          select round(avg(z."rating"), 2)::text from "better_supabase"."appraisal_review_ratings" z join "better_supabase"."appraisal_reviews" v on v."id" = z."review_id"
          where z."competency_id" = w."id" and v."appraisal_id" = x."id" and v."submitted_at" is not null
        ),
        'calibrated', x."calibrated_competencies" -> w."key") order by w."position")
      from "better_supabase"."appraisal_competencies" w where w."cycle_id" = x."cycle_id"
    ), '[]'::jsonb) else '[]'::jsonb end,
    'reviews', coalesce((
      select jsonb_agg(jsonb_build_object('id', y."id",
        'reviewerId', case when "better_supabase"."appraisal_review_hidden"(y."id") then null else y."reviewer_id" end,
        'kind', y."kind", 'rating', y."rating", 'comments', y."comments", 'submissionId', y."submission_id", 'submittedAt', y."submitted_at",
        'ratings', coalesce((
          select jsonb_agg(jsonb_build_object('competency', w."key", 'rating', z."rating", 'comment', z."comment") order by w."position")
          from "better_supabase"."appraisal_review_ratings" z join "better_supabase"."appraisal_competencies" w on w."id" = z."competency_id"
          where z."review_id" = y."id"
        ), '[]'::jsonb))
        order by y."kind", y."id")
      from "better_supabase"."appraisal_reviews" y
      where y."appraisal_id" = x."id"
        and (appraisal_json.all_reviews or y."reviewer_id" = auth.uid() or ((x."appraisee_id" = auth.uid() and x."status" = 'signed_off'
      and (select z."share_feedback" from "better_supabase"."appraisal_cycles" z where z."id" = x."cycle_id")) and y."submitted_at" is not null))
    ), '[]'::jsonb),
    'calibrations', coalesce((
      select jsonb_agg(jsonb_build_object('id', z."id", 'fromRating', z."from_rating"::text, 'toRating', z."to_rating",
        'competencyRatings', z."competency_ratings",
        'reason', z."reason", 'calibratedBy', z."calibrated_by", 'calibratedAt', z."calibrated_at")
        order by z."calibrated_at", z."id")
      from "better_supabase"."appraisal_calibrations" z where z."appraisal_id" = x."id" and appraisal_json.all_reviews
    ), '[]'::jsonb),
    'goalIds', coalesce((
      select jsonb_agg(w."goal_id" order by w."goal_id") from "better_supabase"."appraisal_goals" w where w."appraisal_id" = x."id"
    ), '[]'::jsonb))
  from "better_supabase"."appraisals" x where x."id" = appraisal_json.appraisal_id
$function$;

CREATE OR REPLACE FUNCTION better_supabase.appraisal_review_hidden (
  review_id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_review "better_supabase"."appraisal_reviews";
  v_row "better_supabase"."appraisals";
  v_mode text;
begin
  select * into v_review from "better_supabase"."appraisal_reviews" x where x."id" = appraisal_review_hidden.review_id;
  if not found then
    return true;
  end if;
  if v_review."kind" <> 'peer' or v_review."reviewer_id" is not distinct from auth.uid() or coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    return false;
  end if;
  select * into v_row from "better_supabase"."appraisals" x where x."id" = v_review."appraisal_id";
  select x."anonymity" into v_mode from "better_supabase"."appraisal_cycles" x where x."id" = v_row."cycle_id";
  return case v_mode
    when 'none' then false
    when 'subject' then coalesce(v_row."appraisee_id" = auth.uid(), false)
    else true
  end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.archive_deal (
  deal     uuid,
  archived boolean
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."deals";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "better_supabase"."deals" x set "archived_at" = case when archive_deal.archived then coalesce(x."archived_at", now()) end
  where x."id" = archive_deal.deal and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.write'), false) and (true or coalesce(x."owner_id" = auth.uid(), false)
      or coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.manage'), false)
      or exists (select 1 from "better_supabase"."deal_members" mm where mm."deal_id" = x."id" and mm."user_id" = auth.uid()))))
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  if archive_deal.archived then
    perform "better_supabase".emit_event('deal.archived', jsonb_build_object('organizationId', v_row."tenant_id", 'dealId', v_row."id", 'subjectType', 'deal', 'subjectId', v_row."id"::text, 'name', v_row."name"), 'deals/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/deals');
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
  from "better_supabase"."activities" x where x."id" = attach_activity_recording.engagement and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false));
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
  insert into "better_supabase"."engagement_recordings" ("tenant_id", "activity_id", "file_id", "filename", "media_type", "language", "created_by")
  select v_tenant, attach_activity_recording.engagement, fx."id", fx."filename", fx."media_type", nullif(trim(attach_activity_recording.language), ''), auth.uid()
  from "better_supabase"."ai_files" fx where fx."id" = attach_activity_recording.file
  on conflict ("activity_id", "file_id") do nothing
  returning "id" into v_recording;
  if v_recording is null then
    raise exception 'the file is already a recording of this engagement' using errcode = '23505', hint = 'ACTIVITY_RECORDING_EXISTS';
  end if;
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = attach_activity_recording.engagement), '[]'::jsonb);
  v_first := v_subjects -> 0;
  perform "better_supabase".emit_event('activity.recorded', jsonb_build_object('organizationId', v_tenant, 'engagementId', attach_activity_recording.engagement, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects, 'recordingId', v_recording), 'engagements/' || attach_activity_recording.engagement::text, (v_tenant::text)::text, null, 'better-supabase/activities');
  perform "better_supabase"."enqueue_job"(queue => 'engagements.transcribe', payload => jsonb_build_object('recordingId', v_recording), dedupe_key => 'engagements.transcribe:' || v_recording::text, dedupe_running => false);
  return (select jsonb_build_object('id', rx."id", 'organizationId', rx."tenant_id", 'engagementId', rx."activity_id", 'fileId', rx."file_id", 'filename', rx."filename", 'mediaType', rx."media_type", 'status', rx."status", 'language', rx."language", 'durationSeconds', rx."duration_seconds", 'error', rx."error", 'model', rx."model", 'segmentCount', (select count(*)::integer from "better_supabase"."engagement_transcript_segments" sc where sc."recording_id" = rx."id"), 'createdBy', rx."created_by", 'createdAt', rx."created_at", 'transcribedAt', rx."transcribed_at") from "better_supabase"."engagement_recordings" rx where rx."id" = v_recording);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.book_series (
  service        uuid,
  resource       uuid,
  starts_at      timestamp with time zone,
  rule           jsonb,
  customer       jsonb,
  skip_conflicts boolean                  DEFAULT false
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_customer jsonb := coalesce(book_series.customer, '{}'::jsonb);
  v_user uuid := auth.uid();
  v_tenant uuid;
  v_tz text;
  v_series "better_supabase"."booking_series"%rowtype;
  v_at timestamptz;
  v_booking jsonb;
  v_booked jsonb := '[]'::jsonb;
  v_skipped jsonb := '[]'::jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."booking_services" where "id" = book_series.service and "active";
  if not found then
    raise exception 'service not found' using errcode = 'P0002', hint = 'BOOKING_SERVICE_NOT_FOUND';
  end if;
  if (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'bookings.manage'), false)) then
    v_user := coalesce(nullif(v_customer ->> 'userId', '')::uuid, v_user);
  elsif not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'bookings.create'), false)) then
    raise exception 'not allowed to book' using errcode = '42501', hint = 'BOOKING_FORBIDDEN';
  else
    v_customer := v_customer || jsonb_build_object('email', coalesce(v_customer ->> 'email', auth.email()));
  end if;
  select "tz" into v_tz from "better_supabase"."booking_resources" where "id" = book_series.resource and "tenant_id" = v_tenant and "active";
  if not found then
    raise exception 'resource not found' using errcode = 'P0002', hint = 'BOOKING_RESOURCE_NOT_FOUND';
  end if;
  v_tz := coalesce(nullif(book_series.rule ->> 'tz', ''), v_tz);
  insert into "better_supabase"."booking_series" ("tenant_id", "service_id", "resource_id", "rule", "starts_at", "tz", "customer_name", "customer_email", "customer_id", "created_by")
  values (v_tenant, book_series.service, book_series.resource, book_series.rule - 'tz', book_series.starts_at, v_tz, v_customer ->> 'name', lower(v_customer ->> 'email'), v_user, auth.uid())
  returning * into v_series;
  for v_at in select t from "better_supabase"."booking_series_starts"(book_series.rule, book_series.starts_at, v_tz) t loop
    begin
      v_booking := "better_supabase"."place_booking"(book_series.service, book_series.resource, v_at, v_customer, true, v_user);
      update "better_supabase"."bookings" set "series_id" = v_series."id" where "id" = (v_booking ->> 'id')::uuid;
      v_booked := v_booked || jsonb_build_array((v_booking - 'accessToken') || jsonb_build_object('seriesId', v_series."id"));
    exception when sqlstate '23P01' then
      if not coalesce(book_series.skip_conflicts, false) then
        raise exception 'an occurrence is not an open slot' using errcode = '23P01', hint = 'BOOKING_SERIES_CONFLICT';
      end if;
      v_skipped := v_skipped || jsonb_build_array(v_at);
    end;
  end loop;
  if jsonb_array_length(v_booked) = 0 then
    raise exception 'no occurrence is an open slot' using errcode = '23P01', hint = 'BOOKING_SERIES_CONFLICT';
  end if;
  update "better_supabase"."booking_series" set "ends_at" = ((v_booked -> -1) ->> 'endsAt')::timestamptz where "id" = v_series."id"
  returning * into v_series;
  return jsonb_build_object('series', jsonb_build_object('id', v_series."id", 'organizationId', v_series."tenant_id"::text, 'serviceId', v_series."service_id", 'resourceId', v_series."resource_id", 'rule', v_series."rule", 'startsAt', v_series."starts_at", 'tz', v_series."tz", 'customerName', v_series."customer_name", 'customerEmail', v_series."customer_email", 'customerUserId', v_series."customer_id", 'status', v_series."status", 'endsAt', v_series."ends_at", 'createdAt', v_series."created_at"), 'bookings', v_booked, 'skipped', v_skipped);
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
  v_entry uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_pass from "better_supabase"."passes" x where x."id" = book_with_credit.pass_id for update;
  if not found or not (coalesce(v_pass."holder_id" = auth.uid(), false) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_pass."tenant_id", 'passes.manage'), false))) then
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
  if book_with_credit.starts_at < v_pass."starts_at" or (v_pass."expires_at" is not null and book_with_credit.starts_at >= v_pass."expires_at") then
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
    coalesce(book_with_credit.customer, '{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object('userId', v_pass."holder_id", 'name', v_pass."holder_name", 'email', v_pass."holder_email")), true);
  v_entry := "better_supabase"."ledger_post"(v_pass."tenant_id", 'pass.credit_used',
      jsonb_build_array(
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_pass."tenant_id", 'pass_credits', 'pass:' || v_pass."id"::text, 'Pass credits', 'credit', 0::smallint,
    'passes', v_pass."id"::text, v_pass."holder_id", true, 'passes.read', 'passes', jsonb_build_object('passId', v_pass."id")), 'amount', -1),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_pass."tenant_id", 'pass_credits_pool', 'pass-credits:pool', 'Pass credits pool', 'credit', 0::smallint,
    null, null, null, true, 'passes.read', 'passes', null), 'amount', 1)),
      'bookings', (v_booking ->> 'id')::uuid::text, null, 'pass-credit:' || (v_booking ->> 'id')::uuid::text || ':booking', clock_timestamp(),
      jsonb_build_object('passId', v_pass."id", 'reason', 'booking'));
  update "better_supabase"."passes" x set "uses" = x."uses" + 1, "updated_at" = now()
  where x."id" = v_pass."id";
  perform "better_supabase".emit_event('pass.credit_used', jsonb_build_object('organizationId', v_pass."tenant_id"::text, 'id', v_pass."id", 'entryId', v_entry, 'bookingId', (v_booking ->> 'id')::uuid), 'passes/' || v_pass."id"::text, (v_pass."tenant_id")::text, null, 'better-supabase/passes');
  perform better_supabase.audit_event(
    event_type => 'pass.credit_used',
    category => 'access',
    target_type => 'pass',
    record_id => v_pass."id"::text,
    summary => 'booked with a credit of pass',
    tenant => (v_pass."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_pass."tenant_id"::text, 'id', v_pass."id", 'entryId', v_entry, 'bookingId', (v_booking ->> 'id')::uuid)
  );
  return (v_booking - 'accessToken') || jsonb_build_object('passId', v_pass."id", 'creditsLeft', v_pass."uses_allowed" - v_pass."uses" - 1);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.booking_slots (
  service       uuid,
  range_start   timestamp with time zone,
  range_end     timestamp with time zone,
  tz            text,
  only_resource uuid
)
  RETURNS TABLE (
    resource_id uuid,
    starts_at   timestamp with time zone,
    ends_at     timestamp with time zone,
    local_start timestamp without time zone,
    seats       integer
  )
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_service record;
  v_resource record;
  v_open tstzmultirange;
  v_window tstzrange;
  v_floor timestamptz;
  v_step interval;
  v_at timestamptz;
  v_block tstzrange;
  v_free integer;
  v_busy tstzmultirange := '{}'::tstzmultirange;
begin
  select sv."tenant_id" as tenant, sv."duration" as duration, sv."buffer_before" as before, sv."buffer_after" as after,
      sv."resource_kinds" as kinds, sv."step" as step, sv."min_notice" as notice
    into v_service
    from "better_supabase"."booking_services" sv where sv."id" = booking_slots.service and sv."active";
  if not found or booking_slots.range_end is null or booking_slots.range_start is null then
    return;
  end if;
  v_step := coalesce(v_service.step, v_service.duration);
  v_floor := greatest(booking_slots.range_start, now() + v_service.notice);
  for v_resource in
    select rs."id" as id, rs."tz" as tz, rs."capacity" as capacity, case when rs."check_busy" then rs."host_id" end as host
    from "better_supabase"."booking_resources" rs
    where rs."tenant_id" = v_service.tenant and rs."active"
      and (cardinality(v_service.kinds) = 0 or rs."kind" = any (v_service.kinds))
      and (booking_slots.only_resource is null or rs."id" = booking_slots.only_resource)
    order by rs."name", rs."id"
  loop
    select coalesce(range_agg(tstzrange((d.day + a."starts_at") at time zone v_resource.tz, (d.day + a."ends_at") at time zone v_resource.tz)), '{}'::tstzmultirange)
      into v_open
      from (
        select g::date as day
        from generate_series((v_floor at time zone v_resource.tz)::date - 1, (booking_slots.range_end at time zone v_resource.tz)::date, interval '1 day') g
      ) d
      join "better_supabase"."booking_availability" a on a."resource_id" = v_resource.id and a."weekday" = extract(isodow from d.day)::integer;
    v_open := v_open + coalesce((select range_agg(e."during") from "better_supabase"."booking_exceptions" e where e."resource_id" = v_resource.id and e."available"), '{}'::tstzmultirange);
    v_open := v_open - coalesce((select range_agg(e."during") from "better_supabase"."booking_exceptions" e where e."resource_id" = v_resource.id and not e."available"), '{}'::tstzmultirange);
    v_busy := '{}'::tstzmultirange;
    if v_resource.host is not null then
      select coalesce(range_agg(tstzrange(bb.starts_at, bb.ends_at)), '{}'::tstzmultirange) into v_busy
      from "better_supabase"."calendar_busy_blocks"(v_service.tenant, array[v_resource.host], v_floor - v_service.before, booking_slots.range_end + v_service.after) bb
      where bb.starts_at < bb.ends_at and not exists (select 1 from "better_supabase"."bookings" bk where bk."calendar_event_id" = bb.event_id and bk."resource_id" = v_resource.id);
    end if;
    for v_window in select w from unnest(v_open) w loop
      v_at := lower(v_window);
      if v_at < v_floor then
        v_at := v_at + ceil(extract(epoch from (v_floor - v_at)) / extract(epoch from v_step)) * v_step;
      end if;
      while v_at + v_service.duration <= upper(v_window) and v_at + v_service.duration <= booking_slots.range_end loop
        v_block := tstzrange(v_at - v_service.before, v_at + v_service.duration + v_service.after);
        select count(*)::integer into v_free
        from generate_series(1, v_resource.capacity) seat
        where not exists (
          select 1 from "better_supabase"."bookings" bk
          where bk."resource_id" = v_resource.id and bk."seat" = seat.seat
            and (bk."status" = 'confirmed' or (bk."status" = 'hold' and bk."hold_expires_at" > now())) and bk."blocked" && v_block
        );
        if v_free > 0 and not (v_busy && v_block) then
          resource_id := v_resource.id;
          starts_at := v_at;
          ends_at := v_at + v_service.duration;
          local_start := v_at at time zone coalesce(booking_slots.tz, v_resource.tz);
          seats := v_free;
          return next;
        end if;
        v_at := v_at + v_step;
      end loop;
    end loop;
  end loop;
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
    select p."id", p."owner_id" into v_person, v_person_owner
    from "better_supabase"."people" p
    where p."tenant_id" = v_tenant and p."archived_at" is null and p."merged_into" is null
      and ((new."customer_id" is not null and p."user_id" = new."customer_id")
        or (new."customer_email" is not null and lower(p."email") = lower(new."customer_email")))
    order by (new."customer_id" is not null and p."user_id" = new."customer_id") desc, p."created_at"
    limit 1;
    v_owner := coalesce(v_owner, v_person_owner);
    select left(coalesce(sv."name", 'Booking') || coalesce(' with ' || nullif(trim(new."customer_name"), ''), ''), 500)
    into v_title
    from "better_supabase"."booking_services" sv where sv."id" = new."service_id";
    insert into "better_supabase"."activities" ("tenant_id", "type", "title", "body", "owner_id", "due_at", "duration_seconds", "external_ref", "created_by")
    values (v_tenant, 'meeting', coalesce(v_title, 'Booking'), new."notes", v_owner, lower(new."during"), extract(epoch from upper(new."during") - lower(new."during"))::integer, v_ref, new."created_by")
    on conflict ("tenant_id", "external_ref") where "external_ref" is not null do update set
      "due_at" = excluded."due_at", "duration_seconds" = excluded."duration_seconds",
      "done_at" = null, "outcome" = null, "updated_at" = now()
    returning "id", (xmax = 0) into v_id, v_inserted;
    if v_person is not null then
      insert into "better_supabase"."engagement_subjects" ("tenant_id", "activity_id", "subject_type", "subject_id", "position")
      values (v_tenant, v_id, 'person', v_person::text, 1)
      on conflict do nothing;
      insert into "better_supabase"."engagement_subjects" ("tenant_id", "activity_id", "subject_type", "subject_id", "position")
      select v_tenant, v_id, 'company', c."id"::text, 2
      from "better_supabase"."company_people" k
      join "better_supabase"."companies" c on c."id" = k."company_id"
      where k."person_id" = v_person and c."archived_at" is null
      order by k."is_primary" desc, k."created_at"
      limit 1
      on conflict do nothing;
    end if;
    v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = v_id), '[]'::jsonb);
    v_first := v_subjects -> 0;
    if v_inserted then
      perform "better_supabase".emit_event('activity.logged', jsonb_build_object('organizationId', v_tenant, 'engagementId', v_id, 'type', 'meeting', 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects), 'engagements/' || v_id::text, (v_tenant::text)::text, null, 'better-supabase/activities');
    else
      perform "better_supabase".emit_event('activity.updated', jsonb_build_object('organizationId', v_tenant, 'engagementId', v_id, 'type', 'meeting', 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects), 'engagements/' || v_id::text, (v_tenant::text)::text, null, 'better-supabase/activities');
    end if;
  elsif new."status" = 'cancelled' and tg_op = 'UPDATE' and old."status" = 'confirmed' then
    update "better_supabase"."activities" x set
      "done_at" = coalesce(new."cancelled_at", now()),
      "outcome" = left('cancelled' || coalesce(': ' || nullif(trim(new."cancel_reason"), ''), ''), 500),
      "updated_at" = now()
    where x."tenant_id" = v_tenant and x."external_ref" = v_ref and x."done_at" is null
    returning x."id" into v_id;
    if v_id is not null then
    v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = v_id), '[]'::jsonb);
    v_first := v_subjects -> 0;
      perform "better_supabase".emit_event('activity.completed', jsonb_build_object('organizationId', v_tenant, 'engagementId', v_id, 'type', 'meeting', 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects), 'engagements/' || v_id::text, (v_tenant::text)::text, null, 'better-supabase/activities');
    end if;
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_deal_guard()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_claims text;
begin
  if tg_op = 'INSERT' then
    new."closed_at" := case when new."outcome" <> 'open' then now() end;
    if new."owner_id" is not null then
      insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
    values (new."tenant_id", new."owner_id", 'deal', new."id"::text, 'participating')
    on conflict do nothing;
    end if;
    return new;
  end if;
  if old."locked" and not (auth.role() = 'service_role') and (
      new."name" is distinct from old."name"
      or new."company_type" is distinct from old."company_type"
      or new."company_id" is distinct from old."company_id"
      or new."motion" is distinct from old."motion"
      or new."priority" is distinct from old."priority"
      or new."owner_id" is distinct from old."owner_id"
      or new."product" is distinct from old."product"
      or new."seats" is distinct from old."seats"
      or new."amount" is distinct from old."amount"
      or new."existing_amount" is distinct from old."existing_amount"
      or new."currency" is distinct from old."currency"
      or new."value_period" is distinct from old."value_period"
      or new."pipeline_id" is distinct from old."pipeline_id"
      or new."stage_id" is distinct from old."stage_id"
      or new."probability" is distinct from old."probability"
      or new."forecast_category" is distinct from old."forecast_category"
      or new."expected_close_on" is distinct from old."expected_close_on"
      or new."next_step" is distinct from old."next_step"
      or new."next_at" is distinct from old."next_at"
      or new."next_kind" is distinct from old."next_kind"
      or new."flags" is distinct from old."flags"
      or new."source" is distinct from old."source"
      or new."lost_reason" is distinct from old."lost_reason"
    ) then
    raise exception 'the deal is locked; only its note can change' using errcode = '55000', hint = 'DEAL_LOCKED';
  end if;
  if new."opened_on" is distinct from old."opened_on" and not (auth.role() = 'service_role') then
    raise exception 'the open date never moves' using errcode = '22023', hint = 'DEAL_OPENED_ON_FIXED';
  end if;
  if new."expected_close_on" > old."expected_close_on" and old."outcome" = 'open' then
    new."slipped_from" := coalesce(old."slipped_from", old."expected_close_on");
    new."push_count" := old."push_count" + 1;
  end if;
  if new."forecast_category" is distinct from old."forecast_category" and new."outcome" <> 'open' and old."outcome" <> 'open' then
    raise exception 'a closed deal is called by its stage, not a forecast' using errcode = '22023', hint = 'DEAL_FORECAST_CLOSED';
  end if;
  if new."outcome" is distinct from old."outcome" then
    new."closed_at" := case when new."outcome" <> 'open' then now() end;
    if new."outcome" = 'open' then
      new."lost_reason" := null;
      perform "better_supabase".emit_event('deal.reopened', jsonb_build_object('organizationId', new."tenant_id", 'dealId', new."id", 'subjectType', 'deal', 'subjectId', new."id"::text, 'name', new."name"), 'deals/' || new."id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/deals');
    else
      perform "better_supabase".emit_event('deal.closed', jsonb_build_object('organizationId', new."tenant_id", 'dealId', new."id", 'subjectType', 'deal', 'subjectId', new."id"::text, 'name', new."name", 'outcome', new."outcome", 'amount', new."amount"::text, 'currency', new."currency", 'reason', new."lost_reason"), 'deals/' || new."id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/deals');
    end if;
    if better_supabase.import_run() is null then
      v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'deal.closed',
      'tenant', new."tenant_id",
      'actor', auth.uid(),
      'subject_type', 'deal',
      'subject_id', new."id"::text,
      'summary', new."name",
      'key', 'deal.outcome:' || new."id"::text || ':' || new."outcome" || ':' || extract(epoch from now())::text,
      'data', jsonb_build_object('dealId', new."id", 'outcome', new."outcome")
    ));
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
  end if;
  if new."owner_id" is not null and new."owner_id" is distinct from old."owner_id" then
    insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
    values (new."tenant_id", new."owner_id", 'deal', new."id"::text, 'participating')
    on conflict do nothing;
  end if;
  new."updated_at" := now();
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_field_history_company()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  insert into "better_supabase"."field_changes" ("tenant_id", "subject_type", "subject_id", "field", "old_value", "new_value", "changed_by")
  select new."tenant_id", 'company', new."id"::text, x.field, x.old_value, x.new_value, auth.uid()
  from (values
      ('owner_id', to_jsonb(old."owner_id"), to_jsonb(new."owner_id")),
      ('lifecycle', to_jsonb(old."lifecycle"), to_jsonb(new."lifecycle"))
  ) as x (field, old_value, new_value)
  where x.old_value is distinct from x.new_value;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_field_history_deal()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  insert into "better_supabase"."field_changes" ("tenant_id", "subject_type", "subject_id", "field", "old_value", "new_value", "changed_by")
  select new."tenant_id", 'deal', new."id"::text, x.field, x.old_value, x.new_value, auth.uid()
  from (values
      ('amount', to_jsonb(old."amount"), to_jsonb(new."amount")),
      ('stage_id', to_jsonb(old."stage_id"), to_jsonb(new."stage_id")),
      ('owner_id', to_jsonb(old."owner_id"), to_jsonb(new."owner_id")),
      ('expected_close_on', to_jsonb(old."expected_close_on"), to_jsonb(new."expected_close_on"))
  ) as x (field, old_value, new_value)
  where x.old_value is distinct from x.new_value;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_pipeline_application()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_category text;
  v_outcome text;
  v_stage_name text;
  v_claims text;
begin
  if tg_op = 'UPDATE' and new."stage_id" is not distinct from old."stage_id" and new."pipeline_id" is not distinct from old."pipeline_id" then
  -- The owner watches the record; a level they already chose stays.
  if new."owner_id" is not null and (tg_op = 'INSERT' or new."owner_id" is distinct from old."owner_id") then
    insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
    values (new."tenant_id", new."owner_id", 'application', new."id"::text, 'participating')
    on conflict do nothing;
  end if;
    return new;
  end if;
  if new."pipeline_id" is null then
    if new."stage_id" is not null then
      select s."pipeline_id" into new."pipeline_id" from "better_supabase"."pipeline_stages" s where s."id" = new."stage_id";
    else
      new."pipeline_id" := "better_supabase"."default_pipeline"(new."tenant_id", 'application', new."job_id"::text);
    end if;
  end if;
  if new."stage_id" is null then
    select s."id" into new."stage_id" from "better_supabase"."pipeline_stages" s
    where s."pipeline_id" = new."pipeline_id" and s."outcome" = 'open' and s."archived_at" is null
    order by s."rank" collate "C"
    limit 1;
  end if;
  select s."category", s."outcome", s."name"
    into v_category, v_outcome, v_stage_name
  from "better_supabase"."pipeline_stages" s
  join "better_supabase"."pipelines" p on p."id" = s."pipeline_id"
  where s."id" = new."stage_id"
    and s."pipeline_id" = new."pipeline_id"
    and s."archived_at" is null
    and p."archived_at" is null
    and p."tenant_id"::text = new."tenant_id"::text
    and p."subject_type" = 'application'
    and p."scope_id" is not distinct from new."job_id"::text;
  if not found then
    raise exception 'the stage is not an active stage of this record''s pipeline' using errcode = '22023', hint = 'PIPELINE_STAGE_INVALID';
  end if;
  if tg_op = 'INSERT' or new."stage_id" is distinct from old."stage_id" then
    if tg_op = 'UPDATE' and old."stage_id" is not null
      and coalesce(current_setting('bsb.lane_move', true), '') <> old."stage_id"::text || ':' || new."stage_id"::text
      and exists (select 1 from "better_supabase"."pipeline_transitions" x where x."pipeline_id" = new."pipeline_id")
      and not exists (
        select 1 from "better_supabase"."pipeline_transitions" x
        where x."from_stage_id" = old."stage_id" and x."to_stage_id" = new."stage_id"
      ) then
      raise exception 'that stage change is not allowed in this pipeline' using errcode = '22023', hint = 'PIPELINE_TRANSITION_INVALID';
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_pipeline_stage_change"(text, text, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::uuid, $4::uuid)', v_hook::oid::regproc)
        using 'application', new."id"::text, case when tg_op = 'UPDATE' then old."stage_id" end, new."stage_id";
    end if;
  end;
    new."stage_entered_at" := now();
    update "better_supabase"."pipeline_stage_history" set "exited_at" = now()
    where "subject_type" = 'application' and "subject_id" = new."id"::text and "exited_at" is null;
    insert into "better_supabase"."pipeline_stage_history" ("tenant_id", "subject_type", "subject_id", "pipeline_id", "from_stage_id", "to_stage_id", "stage_name", "category", "outcome", "amount", "currency", "actor_id")
    values (new."tenant_id", 'application', new."id"::text, new."pipeline_id", case when tg_op = 'UPDATE' then old."stage_id" end, new."stage_id", v_stage_name, v_category, v_outcome, null, null, auth.uid());
    if tg_op = 'UPDATE' then
      perform "better_supabase".emit_event('pipeline.stage_changed', jsonb_build_object('organizationId', new."tenant_id"::text, 'subjectType', 'application', 'subjectId', new."id"::text, 'pipelineId', new."pipeline_id", 'fromStageId', old."stage_id", 'toStageId', new."stage_id", 'category', v_category, 'outcome', v_outcome), 'pipelines/' || new."pipeline_id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/pipelines');
    end if;
    if tg_op = 'UPDATE' then
      if better_supabase.import_run() is null then
        v_claims := current_setting('request.jwt.claims', true);
        perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
        perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'pipeline.stage_changed',
        'tenant', new."tenant_id",
        'actor', auth.uid(),
        'subject_type', 'application',
        'subject_id', new."id"::text,
        'summary', v_stage_name,
        'key', 'pipeline.stage_changed:' || new."id"::text || ':' || new."stage_id"::text || ':' || extract(epoch from now())::text,
        'data', jsonb_build_object('pipelineId', new."pipeline_id", 'fromStageId', old."stage_id", 'toStageId', new."stage_id", 'outcome', v_outcome)
      ));
        perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
      end if;
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_pipeline_stage_change"(text, text, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::uuid)', v_hook::oid::regproc)
        using 'application', new."id"::text, new."stage_id";
    end if;
  end;
  end if;
  -- The owner watches the record; a level they already chose stays.
  if new."owner_id" is not null and (tg_op = 'INSERT' or new."owner_id" is distinct from old."owner_id") then
    insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
    values (new."tenant_id", new."owner_id", 'application', new."id"::text, 'participating')
    on conflict do nothing;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_pipeline_case()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_category text;
  v_outcome text;
  v_stage_name text;
  v_claims text;
begin
  if tg_op = 'UPDATE' and new."stage_id" is not distinct from old."stage_id" and new."pipeline_id" is not distinct from old."pipeline_id" then
    return new;
  end if;
  if new."pipeline_id" is null then
    if new."stage_id" is not null then
      select s."pipeline_id" into new."pipeline_id" from "better_supabase"."pipeline_stages" s where s."id" = new."stage_id";
    else
      new."pipeline_id" := "better_supabase"."default_pipeline"(new."tenant_id", 'case', new."kind_id"::text);
    end if;
  end if;
  if new."stage_id" is null then
    select s."id" into new."stage_id" from "better_supabase"."pipeline_stages" s
    where s."pipeline_id" = new."pipeline_id" and s."outcome" = 'open' and s."archived_at" is null
    order by s."rank" collate "C"
    limit 1;
  end if;
  select s."category", s."outcome", s."name"
    into v_category, v_outcome, v_stage_name
  from "better_supabase"."pipeline_stages" s
  join "better_supabase"."pipelines" p on p."id" = s."pipeline_id"
  where s."id" = new."stage_id"
    and s."pipeline_id" = new."pipeline_id"
    and s."archived_at" is null
    and p."archived_at" is null
    and p."tenant_id"::text = new."tenant_id"::text
    and p."subject_type" = 'case'
    and p."scope_id" is not distinct from new."kind_id"::text;
  if not found then
    raise exception 'the stage is not an active stage of this record''s pipeline' using errcode = '22023', hint = 'PIPELINE_STAGE_INVALID';
  end if;
  if tg_op = 'INSERT' or new."stage_id" is distinct from old."stage_id" then
    if tg_op = 'UPDATE' and old."stage_id" is not null
      and coalesce(current_setting('bsb.lane_move', true), '') <> old."stage_id"::text || ':' || new."stage_id"::text
      and exists (select 1 from "better_supabase"."pipeline_transitions" x where x."pipeline_id" = new."pipeline_id")
      and not exists (
        select 1 from "better_supabase"."pipeline_transitions" x
        where x."from_stage_id" = old."stage_id" and x."to_stage_id" = new."stage_id"
      ) then
      raise exception 'that stage change is not allowed in this pipeline' using errcode = '22023', hint = 'PIPELINE_TRANSITION_INVALID';
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_pipeline_stage_change"(text, text, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::uuid, $4::uuid)', v_hook::oid::regproc)
        using 'case', new."id"::text, case when tg_op = 'UPDATE' then old."stage_id" end, new."stage_id";
    end if;
  end;
    new."stage_entered_at" := now();
    update "better_supabase"."pipeline_stage_history" set "exited_at" = now()
    where "subject_type" = 'case' and "subject_id" = new."id"::text and "exited_at" is null;
    insert into "better_supabase"."pipeline_stage_history" ("tenant_id", "subject_type", "subject_id", "pipeline_id", "from_stage_id", "to_stage_id", "stage_name", "category", "outcome", "amount", "currency", "actor_id")
    values (new."tenant_id", 'case', new."id"::text, new."pipeline_id", case when tg_op = 'UPDATE' then old."stage_id" end, new."stage_id", v_stage_name, v_category, v_outcome, null, null, auth.uid());
    if tg_op = 'UPDATE' then
      perform "better_supabase".emit_event('pipeline.stage_changed', jsonb_build_object('organizationId', new."tenant_id"::text, 'subjectType', 'case', 'subjectId', new."id"::text, 'pipelineId', new."pipeline_id", 'fromStageId', old."stage_id", 'toStageId', new."stage_id", 'category', v_category, 'outcome', v_outcome), 'pipelines/' || new."pipeline_id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/pipelines');
    end if;
    if tg_op = 'UPDATE' then
      if better_supabase.import_run() is null then
        v_claims := current_setting('request.jwt.claims', true);
        perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
        perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'pipeline.stage_changed',
        'tenant', new."tenant_id",
        'actor', auth.uid(),
        'subject_type', 'case',
        'subject_id', new."id"::text,
        'summary', v_stage_name,
        'key', 'pipeline.stage_changed:' || new."id"::text || ':' || new."stage_id"::text || ':' || extract(epoch from now())::text,
        'data', jsonb_build_object('pipelineId', new."pipeline_id", 'fromStageId', old."stage_id", 'toStageId', new."stage_id", 'outcome', v_outcome)
      ));
        perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
      end if;
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_pipeline_stage_change"(text, text, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::uuid)', v_hook::oid::regproc)
        using 'case', new."id"::text, new."stage_id";
    end if;
  end;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_pipeline_deal()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_category text;
  v_outcome text;
  v_stage_name text;
  v_claims text;
begin
  if tg_op = 'UPDATE' and new."stage_id" is not distinct from old."stage_id" and new."pipeline_id" is not distinct from old."pipeline_id" then
  -- The owner watches the record; a level they already chose stays.
  if new."owner_id" is not null and (tg_op = 'INSERT' or new."owner_id" is distinct from old."owner_id") then
    insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
    values (new."tenant_id", new."owner_id", 'deal', new."id"::text, 'participating')
    on conflict do nothing;
  end if;
    return new;
  end if;
  if new."pipeline_id" is null then
    if new."stage_id" is not null then
      select s."pipeline_id" into new."pipeline_id" from "better_supabase"."pipeline_stages" s where s."id" = new."stage_id";
    else
      new."pipeline_id" := "better_supabase"."default_pipeline"(new."tenant_id", 'deal', null);
    end if;
  end if;
  if new."stage_id" is null then
    select s."id" into new."stage_id" from "better_supabase"."pipeline_stages" s
    where s."pipeline_id" = new."pipeline_id" and s."outcome" = 'open' and s."archived_at" is null
    order by s."rank" collate "C"
    limit 1;
  end if;
  select s."category", s."outcome", s."name"
    into v_category, v_outcome, v_stage_name
  from "better_supabase"."pipeline_stages" s
  join "better_supabase"."pipelines" p on p."id" = s."pipeline_id"
  where s."id" = new."stage_id"
    and s."pipeline_id" = new."pipeline_id"
    and s."archived_at" is null
    and p."archived_at" is null
    and p."tenant_id"::text = new."tenant_id"::text
    and p."subject_type" = 'deal'
    and p."scope_id" is not distinct from null;
  if not found then
    raise exception 'the stage is not an active stage of this record''s pipeline' using errcode = '22023', hint = 'PIPELINE_STAGE_INVALID';
  end if;
  if tg_op = 'INSERT' or new."stage_id" is distinct from old."stage_id" then
    if tg_op = 'UPDATE' and old."stage_id" is not null
      and coalesce(current_setting('bsb.lane_move', true), '') <> old."stage_id"::text || ':' || new."stage_id"::text
      and exists (select 1 from "better_supabase"."pipeline_transitions" x where x."pipeline_id" = new."pipeline_id")
      and not exists (
        select 1 from "better_supabase"."pipeline_transitions" x
        where x."from_stage_id" = old."stage_id" and x."to_stage_id" = new."stage_id"
      ) then
      raise exception 'that stage change is not allowed in this pipeline' using errcode = '22023', hint = 'PIPELINE_TRANSITION_INVALID';
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_pipeline_stage_change"(text, text, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::uuid, $4::uuid)', v_hook::oid::regproc)
        using 'deal', new."id"::text, case when tg_op = 'UPDATE' then old."stage_id" end, new."stage_id";
    end if;
  end;
    new."stage_entered_at" := now();
    update "better_supabase"."pipeline_stage_history" set "exited_at" = now()
    where "subject_type" = 'deal' and "subject_id" = new."id"::text and "exited_at" is null;
    insert into "better_supabase"."pipeline_stage_history" ("tenant_id", "subject_type", "subject_id", "pipeline_id", "from_stage_id", "to_stage_id", "stage_name", "category", "outcome", "amount", "currency", "actor_id")
    values (new."tenant_id", 'deal', new."id"::text, new."pipeline_id", case when tg_op = 'UPDATE' then old."stage_id" end, new."stage_id", v_stage_name, v_category, v_outcome, new."amount", new."currency", auth.uid());
    if tg_op = 'UPDATE' then
      perform "better_supabase".emit_event('pipeline.stage_changed', jsonb_build_object('organizationId', new."tenant_id"::text, 'subjectType', 'deal', 'subjectId', new."id"::text, 'pipelineId', new."pipeline_id", 'fromStageId', old."stage_id", 'toStageId', new."stage_id", 'category', v_category, 'outcome', v_outcome), 'pipelines/' || new."pipeline_id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/pipelines');
    end if;
    if tg_op = 'UPDATE' then
      if better_supabase.import_run() is null then
        v_claims := current_setting('request.jwt.claims', true);
        perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
        perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'pipeline.stage_changed',
        'tenant', new."tenant_id",
        'actor', auth.uid(),
        'subject_type', 'deal',
        'subject_id', new."id"::text,
        'summary', v_stage_name,
        'key', 'pipeline.stage_changed:' || new."id"::text || ':' || new."stage_id"::text || ':' || extract(epoch from now())::text,
        'data', jsonb_build_object('pipelineId', new."pipeline_id", 'fromStageId', old."stage_id", 'toStageId', new."stage_id", 'outcome', v_outcome)
      ));
        perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
      end if;
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_pipeline_stage_change"(text, text, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::uuid)', v_hook::oid::regproc)
        using 'deal', new."id"::text, new."stage_id";
    end if;
  end;
  end if;
  -- The owner watches the record; a level they already chose stays.
  if new."owner_id" is not null and (tg_op = 'INSERT' or new."owner_id" is distinct from old."owner_id") then
    insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
    values (new."tenant_id", new."owner_id", 'deal', new."id"::text, 'participating')
    on conflict do nothing;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_pipeline_maintenance_request()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_category text;
  v_outcome text;
  v_stage_name text;
  v_claims text;
begin
  if tg_op = 'UPDATE' and new."stage_id" is not distinct from old."stage_id" and new."pipeline_id" is not distinct from old."pipeline_id" then
    return new;
  end if;
  if new."pipeline_id" is null then
    if new."stage_id" is not null then
      select s."pipeline_id" into new."pipeline_id" from "better_supabase"."pipeline_stages" s where s."id" = new."stage_id";
    else
      new."pipeline_id" := "better_supabase"."default_pipeline"(new."tenant_id", 'maintenance_request', new."team_id"::text);
    end if;
  end if;
  if new."stage_id" is null then
    select s."id" into new."stage_id" from "better_supabase"."pipeline_stages" s
    where s."pipeline_id" = new."pipeline_id" and s."outcome" = 'open' and s."archived_at" is null
    order by s."rank" collate "C"
    limit 1;
  end if;
  select s."category", s."outcome", s."name"
    into v_category, v_outcome, v_stage_name
  from "better_supabase"."pipeline_stages" s
  join "better_supabase"."pipelines" p on p."id" = s."pipeline_id"
  where s."id" = new."stage_id"
    and s."pipeline_id" = new."pipeline_id"
    and s."archived_at" is null
    and p."archived_at" is null
    and p."tenant_id"::text = new."tenant_id"::text
    and p."subject_type" = 'maintenance_request'
    and p."scope_id" is not distinct from new."team_id"::text;
  if not found then
    raise exception 'the stage is not an active stage of this record''s pipeline' using errcode = '22023', hint = 'PIPELINE_STAGE_INVALID';
  end if;
  if tg_op = 'INSERT' or new."stage_id" is distinct from old."stage_id" then
    if tg_op = 'UPDATE' and old."stage_id" is not null
      and coalesce(current_setting('bsb.lane_move', true), '') <> old."stage_id"::text || ':' || new."stage_id"::text
      and exists (select 1 from "better_supabase"."pipeline_transitions" x where x."pipeline_id" = new."pipeline_id")
      and not exists (
        select 1 from "better_supabase"."pipeline_transitions" x
        where x."from_stage_id" = old."stage_id" and x."to_stage_id" = new."stage_id"
      ) then
      raise exception 'that stage change is not allowed in this pipeline' using errcode = '22023', hint = 'PIPELINE_TRANSITION_INVALID';
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_pipeline_stage_change"(text, text, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::uuid, $4::uuid)', v_hook::oid::regproc)
        using 'maintenance_request', new."id"::text, case when tg_op = 'UPDATE' then old."stage_id" end, new."stage_id";
    end if;
  end;
    new."stage_entered_at" := now();
    update "better_supabase"."pipeline_stage_history" set "exited_at" = now()
    where "subject_type" = 'maintenance_request' and "subject_id" = new."id"::text and "exited_at" is null;
    insert into "better_supabase"."pipeline_stage_history" ("tenant_id", "subject_type", "subject_id", "pipeline_id", "from_stage_id", "to_stage_id", "stage_name", "category", "outcome", "amount", "currency", "actor_id")
    values (new."tenant_id", 'maintenance_request', new."id"::text, new."pipeline_id", case when tg_op = 'UPDATE' then old."stage_id" end, new."stage_id", v_stage_name, v_category, v_outcome, null, null, auth.uid());
    if tg_op = 'UPDATE' then
      perform "better_supabase".emit_event('pipeline.stage_changed', jsonb_build_object('organizationId', new."tenant_id"::text, 'subjectType', 'maintenance_request', 'subjectId', new."id"::text, 'pipelineId', new."pipeline_id", 'fromStageId', old."stage_id", 'toStageId', new."stage_id", 'category', v_category, 'outcome', v_outcome), 'pipelines/' || new."pipeline_id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/pipelines');
    end if;
    if tg_op = 'UPDATE' then
      if better_supabase.import_run() is null then
        v_claims := current_setting('request.jwt.claims', true);
        perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
        perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'pipeline.stage_changed',
        'tenant', new."tenant_id",
        'actor', auth.uid(),
        'subject_type', 'maintenance_request',
        'subject_id', new."id"::text,
        'summary', v_stage_name,
        'key', 'pipeline.stage_changed:' || new."id"::text || ':' || new."stage_id"::text || ':' || extract(epoch from now())::text,
        'data', jsonb_build_object('pipelineId', new."pipeline_id", 'fromStageId', old."stage_id", 'toStageId', new."stage_id", 'outcome', v_outcome)
      ));
        perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
      end if;
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_pipeline_stage_change"(text, text, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::uuid)', v_hook::oid::regproc)
        using 'maintenance_request', new."id"::text, new."stage_id";
    end if;
  end;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_pipeline_work_item()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_category text;
  v_outcome text;
  v_stage_name text;
  v_claims text;
begin
  if tg_op = 'UPDATE' and new."stage_id" is not distinct from old."stage_id" and new."pipeline_id" is not distinct from old."pipeline_id" then
    return new;
  end if;
  if new."pipeline_id" is null then
    if new."stage_id" is not null then
      select s."pipeline_id" into new."pipeline_id" from "better_supabase"."pipeline_stages" s where s."id" = new."stage_id";
    else
      new."pipeline_id" := "better_supabase"."default_pipeline"(new."tenant_id", 'work_item', new."team_id"::text);
    end if;
  end if;
  if new."stage_id" is null then
    select s."id" into new."stage_id" from "better_supabase"."pipeline_stages" s
    where s."pipeline_id" = new."pipeline_id" and s."outcome" = 'open' and s."archived_at" is null
    order by s."rank" collate "C"
    limit 1;
  end if;
  select s."category", s."outcome", s."name"
    into v_category, v_outcome, v_stage_name
  from "better_supabase"."pipeline_stages" s
  join "better_supabase"."pipelines" p on p."id" = s."pipeline_id"
  where s."id" = new."stage_id"
    and s."pipeline_id" = new."pipeline_id"
    and s."archived_at" is null
    and p."archived_at" is null
    and p."tenant_id"::text = new."tenant_id"::text
    and p."subject_type" = 'work_item'
    and p."scope_id" is not distinct from new."team_id"::text;
  if not found then
    raise exception 'the stage is not an active stage of this record''s pipeline' using errcode = '22023', hint = 'PIPELINE_STAGE_INVALID';
  end if;
  if tg_op = 'INSERT' or new."stage_id" is distinct from old."stage_id" then
    if tg_op = 'UPDATE' and old."stage_id" is not null
      and coalesce(current_setting('bsb.lane_move', true), '') <> old."stage_id"::text || ':' || new."stage_id"::text
      and exists (select 1 from "better_supabase"."pipeline_transitions" x where x."pipeline_id" = new."pipeline_id")
      and not exists (
        select 1 from "better_supabase"."pipeline_transitions" x
        where x."from_stage_id" = old."stage_id" and x."to_stage_id" = new."stage_id"
      ) then
      raise exception 'that stage change is not allowed in this pipeline' using errcode = '22023', hint = 'PIPELINE_TRANSITION_INVALID';
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_pipeline_stage_change"(text, text, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::uuid, $4::uuid)', v_hook::oid::regproc)
        using 'work_item', new."id"::text, case when tg_op = 'UPDATE' then old."stage_id" end, new."stage_id";
    end if;
  end;
    new."stage_entered_at" := now();
    update "better_supabase"."pipeline_stage_history" set "exited_at" = now()
    where "subject_type" = 'work_item' and "subject_id" = new."id"::text and "exited_at" is null;
    insert into "better_supabase"."pipeline_stage_history" ("tenant_id", "subject_type", "subject_id", "pipeline_id", "from_stage_id", "to_stage_id", "stage_name", "category", "outcome", "amount", "currency", "actor_id")
    values (new."tenant_id", 'work_item', new."id"::text, new."pipeline_id", case when tg_op = 'UPDATE' then old."stage_id" end, new."stage_id", v_stage_name, v_category, v_outcome, null, null, auth.uid());
    if tg_op = 'UPDATE' then
      perform "better_supabase".emit_event('pipeline.stage_changed', jsonb_build_object('organizationId', new."tenant_id"::text, 'subjectType', 'work_item', 'subjectId', new."id"::text, 'pipelineId', new."pipeline_id", 'fromStageId', old."stage_id", 'toStageId', new."stage_id", 'category', v_category, 'outcome', v_outcome), 'pipelines/' || new."pipeline_id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/pipelines');
    end if;
    if tg_op = 'UPDATE' then
      if better_supabase.import_run() is null then
        v_claims := current_setting('request.jwt.claims', true);
        perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
        perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'pipeline.stage_changed',
        'tenant', new."tenant_id",
        'actor', auth.uid(),
        'subject_type', 'work_item',
        'subject_id', new."id"::text,
        'summary', v_stage_name,
        'key', 'pipeline.stage_changed:' || new."id"::text || ':' || new."stage_id"::text || ':' || extract(epoch from now())::text,
        'data', jsonb_build_object('pipelineId', new."pipeline_id", 'fromStageId', old."stage_id", 'toStageId', new."stage_id", 'outcome', v_outcome)
      ));
        perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
      end if;
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_pipeline_stage_change"(text, text, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::uuid)', v_hook::oid::regproc)
        using 'work_item', new."id"::text, new."stage_id";
    end if;
  end;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_transition_change_request()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_op jsonb;
  v_flag text;
  v_flags text[];
  v_until timestamptz;
  v_paused boolean;
  v_version uuid;
  v_number integer;
  v_graph jsonb;
begin
  if tg_op = 'INSERT' then
    select v."id", v."version" into v_version, v_number
    from "better_supabase"."workflow_versions" v
    join "better_supabase"."workflow_definitions" d on d."id" = v."definition_id"
    where d."slug" = 'change-requests'
      and v."status"::text = 'published'
      and (d."tenant_id"::text = new."organization_id"::text or d."scope"::text = 'system')
    order by d."tenant_id" is null, v."version" desc
    limit 1;
    if v_version is null then
      raise exception 'the machine''s workflow has no published version' using errcode = '55000', hint = 'STATE_LIFECYCLE_UNPUBLISHED';
    end if;
    v_graph := "better_supabase"."lifecycle_graph"(v_version);
    if new."status" is null then
      new."status" := v_graph ->> 'initial';
    end if;
    if new."status" is null or not ((v_graph -> 'order') ? new."status"::text) then
      raise exception 'that status is not a stage of the machine''s workflow' using errcode = '22023', hint = 'STATE_TRANSITION_INVALID';
    end if;
    
    insert into "better_supabase"."subject_lifecycles" ("tenant_id", "subject_type", "subject_id", "version", "workflow_version_id")
    values (new."organization_id", 'change_request', new."id"::text, v_number, v_version)
    on conflict ("subject_type", "subject_id") do update set
      "version" = excluded."version",
      "workflow_version_id" = excluded."workflow_version_id",
      "updated_at" = now();
    return new;
  end if;
  if new."status" is not distinct from old."status" then
    v_op := nullif(current_setting('better_supabase.lifecycle_op', true), '')::jsonb;
    if v_op is not null and v_op ->> 'machine' = 'change_request' and v_op ->> 'id' = new."id"::text then
      case v_op ->> 'op'
        when 'pause' then
          if (v_op ->> 'until') is not null and (v_op ->> 'until')::timestamptz <= now() then
            raise exception 'a pause must end in the future' using errcode = '22023', hint = 'STATE_PAUSE_INVALID';
          end if;
          insert into "better_supabase"."subject_lifecycles" ("tenant_id", "subject_type", "subject_id", "version", "paused_at", "pause_expires_at", "pause_reason", "paused_by")
          values (new."organization_id", 'change_request', new."id"::text, 1, now(), (v_op ->> 'until')::timestamptz, nullif(v_op ->> 'reason', ''), auth.uid())
          on conflict ("subject_type", "subject_id") do update set
            "paused_at" = excluded."paused_at",
            "pause_expires_at" = excluded."pause_expires_at",
            "pause_reason" = excluded."pause_reason",
            "paused_by" = excluded."paused_by",
            "updated_at" = now();
          perform set_config('better_supabase.lifecycle_changed', '1', true);
          perform "better_supabase".emit_event('status.paused', jsonb_build_object('organizationId', new."organization_id"::text, 'subjectType', 'change_request', 'subjectId', new."id"::text, 'until', v_op ->> 'until', 'reason', nullif(v_op ->> 'reason', '')), 'statuses/change_request/' || new."id"::text, (new."organization_id"::text)::text, null, 'better-supabase/state-machine');
        when 'resume' then
          update "better_supabase"."subject_lifecycles" set "paused_at" = null, "pause_expires_at" = null, "pause_reason" = null, "paused_by" = null, "updated_at" = now()
          where "subject_type" = 'change_request' and "subject_id" = new."id"::text and "paused_at" is not null;
          if found then
            perform set_config('better_supabase.lifecycle_changed', '1', true);
            perform "better_supabase".emit_event('status.resumed', jsonb_build_object('organizationId', new."organization_id"::text, 'subjectType', 'change_request', 'subjectId', new."id"::text), 'statuses/change_request/' || new."id"::text, (new."organization_id"::text)::text, null, 'better-supabase/state-machine');
          end if;
        when 'flag' then
          v_flag := v_op ->> 'flag';
          if v_flag is null or not (v_flag = any ('{}'::text[])) then
            raise exception 'the machine has no such flag' using errcode = '22023', hint = 'STATE_FLAG_UNKNOWN';
          end if;
          select coalesce("flags", '{}') into v_flags from "better_supabase"."subject_lifecycles" where "subject_type" = 'change_request' and "subject_id" = new."id"::text for update;
          v_flags := coalesce(v_flags, '{}');
          if coalesce((v_op ->> 'enabled')::boolean, false) is distinct from (v_flag = any (v_flags)) then
            v_flags := case when coalesce((v_op ->> 'enabled')::boolean, false)
              then v_flags || v_flag else array_remove(v_flags, v_flag) end;
            insert into "better_supabase"."subject_lifecycles" ("tenant_id", "subject_type", "subject_id", "version", "flags")
            values (new."organization_id", 'change_request', new."id"::text, 1, v_flags)
            on conflict ("subject_type", "subject_id") do update set
              "flags" = excluded."flags",
              "updated_at" = now();
            perform set_config('better_supabase.lifecycle_changed', '1', true);
            perform "better_supabase".emit_event('status.flagged', jsonb_build_object('organizationId', new."organization_id"::text, 'subjectType', 'change_request', 'subjectId', new."id"::text, 'flag', v_flag, 'enabled', coalesce((v_op ->> 'enabled')::boolean, false)), 'statuses/change_request/' || new."id"::text, (new."organization_id"::text)::text, null, 'better-supabase/state-machine');
          end if;
        else
          raise exception 'unknown lifecycle change' using errcode = '22023', hint = 'STATE_LIFECYCLE_INVALID';
      end case;
    end if;
    return new;
  end if;
  select "workflow_version_id" into v_version from "better_supabase"."subject_lifecycles"
  where "subject_type" = 'change_request' and "subject_id" = new."id"::text;
  if v_version is null then
    select v."id", v."version" into v_version, v_number
    from "better_supabase"."workflow_versions" v
    join "better_supabase"."workflow_definitions" d on d."id" = v."definition_id"
    where d."slug" = 'change-requests'
      and v."status"::text = 'published'
      and (d."tenant_id"::text = new."organization_id"::text or d."scope"::text = 'system')
    order by d."tenant_id" is null, v."version" desc
    limit 1;
    if v_version is null then
      raise exception 'the machine''s workflow has no published version' using errcode = '55000', hint = 'STATE_LIFECYCLE_UNPUBLISHED';
    end if;
    insert into "better_supabase"."subject_lifecycles" ("tenant_id", "subject_type", "subject_id", "version", "workflow_version_id")
    values (new."organization_id", 'change_request', new."id"::text, v_number, v_version)
    on conflict ("subject_type", "subject_id") do update set
      "version" = excluded."version",
      "workflow_version_id" = excluded."workflow_version_id",
      "updated_at" = now();
  end if;
  v_graph := "better_supabase"."lifecycle_graph"(v_version);
  if not coalesce((v_graph -> 'transitions' -> old."status"::text) ? new."status"::text, false) then
    raise exception 'that status change is not allowed' using errcode = '22023', hint = 'STATE_TRANSITION_INVALID';
  end if;
  select "pause_expires_at", "paused_at" is not null into v_until, v_paused from "better_supabase"."subject_lifecycles" where "subject_type" = 'change_request' and "subject_id" = new."id"::text;
  if coalesce(v_paused, false) then
    if v_until is null or v_until > now() then
      raise exception 'the record is paused; resume it first' using errcode = '55000', hint = 'STATE_PAUSED';
    end if;
    update "better_supabase"."subject_lifecycles" set "paused_at" = null, "pause_expires_at" = null, "pause_reason" = null, "paused_by" = null, "updated_at" = now()
    where "subject_type" = 'change_request' and "subject_id" = new."id"::text;
    perform "better_supabase".emit_event('status.resumed', jsonb_build_object('organizationId', new."organization_id"::text, 'subjectType', 'change_request', 'subjectId', new."id"::text), 'statuses/change_request/' || new."id"::text, (new."organization_id"::text)::text, null, 'better-supabase/state-machine');
  end if;
  insert into "better_supabase"."status_history" ("tenant_id", "subject_type", "subject_id", "from_status", "to_status", "actor_id", "reason", "actor_name", "actor_email", "ip_address", "user_agent")
        values (new."organization_id", 'change_request', new."id"::text, old."status"::text, new."status"::text, coalesce(auth.uid(), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'id', '')::uuid), nullif(current_setting('better_supabase.transition_reason', true), ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'name', ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'email', ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'ip', '')::inet, nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'userAgent', ''));
  
  perform "better_supabase".emit_event('status.changed', jsonb_build_object('organizationId', new."organization_id"::text, 'subjectType', 'change_request', 'subjectId', new."id"::text, 'from', old."status"::text, 'to', new."status"::text, 'reason', nullif(current_setting('better_supabase.transition_reason', true), '')), 'statuses/change_request/' || new."id"::text, (new."organization_id"::text)::text, null, 'better-supabase/state-machine');
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_transition_drive_node()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if tg_op = 'INSERT' then
    
    -- An import run (ADR 0141) may insert a row in any status: one synthetic
    -- imported history row stands for how it got there, and no event fires.
    if better_supabase.import_run() is not null and new."document_status" is not null then
      insert into "better_supabase"."status_history" ("tenant_id", "subject_type", "subject_id", "from_status", "to_status", "actor_id", "reason", "actor_name", "actor_email", "ip_address", "user_agent")
        values (new."tenant_id", 'drive_node', new."id"::text, null::text, new."document_status"::text, coalesce(auth.uid(), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'id', '')::uuid), 'imported', nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'name', ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'email', ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'ip', '')::inet, nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'userAgent', ''));
    end if;
    
    
    return new;
  end if;
  if new."document_status" is not distinct from old."document_status" then
    return new;
  end if;
  if new."document_status" is null or not (old."document_status" is null and new."document_status"::text = 'draft') and not (case old."document_status"::text when 'draft' then new."document_status"::text = any ('{in_review}'::text[]) when 'in_review' then new."document_status"::text = any ('{draft,effective}'::text[]) when 'effective' then new."document_status"::text = any ('{obsolete}'::text[]) else false end) then
    raise exception 'that status change is not allowed' using errcode = '22023', hint = 'STATE_TRANSITION_INVALID';
  end if;
  -- The approvals module sets better_supabase.approval to the request it
  -- just approved before it makes the transition.
  if (case old."document_status"::text when 'in_review' then new."document_status"::text = any ('{effective}'::text[]) else false end)
    and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
    and not exists (
      select 1 from "better_supabase"."approval_requests" a
      where a."id"::text = nullif(current_setting('better_supabase.approval', true), '')
        and a."status" = 'approved'
        and a."subject_type" = 'drive_node'
        and a."subject_id" = new."id"::text
    ) then
    raise exception 'that status change needs an approved request' using errcode = '42501', hint = 'STATE_APPROVAL_REQUIRED';
  end if;
  insert into "better_supabase"."status_history" ("tenant_id", "subject_type", "subject_id", "from_status", "to_status", "actor_id", "reason", "actor_name", "actor_email", "ip_address", "user_agent")
        values (new."tenant_id", 'drive_node', new."id"::text, old."document_status"::text, new."document_status"::text, coalesce(auth.uid(), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'id', '')::uuid), nullif(current_setting('better_supabase.transition_reason', true), ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'name', ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'email', ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'ip', '')::inet, nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'userAgent', ''));
  
  perform "better_supabase".emit_event('status.changed', jsonb_build_object('organizationId', new."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', new."id"::text, 'from', old."document_status"::text, 'to', new."document_status"::text, 'reason', nullif(current_setting('better_supabase.transition_reason', true), '')), 'statuses/drive_node/' || new."id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/state-machine');
  return new;
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
    -- An import run (ADR 0141) may insert a row in any status: one synthetic
    -- imported history row stands for how it got there, and no event fires.
    if better_supabase.import_run() is not null and new."state" is not null then
      insert into "better_supabase"."status_history" ("tenant_id", "subject_type", "subject_id", "from_status", "to_status", "actor_id", "reason", "actor_name", "actor_email", "ip_address", "user_agent")
        values (new."tenant_id", 'work_item', new."id"::text, null::text, new."state"::text, coalesce(auth.uid(), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'id', '')::uuid), 'imported', nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'name', ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'email', ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'ip', '')::inet, nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'userAgent', ''));
    end if;
    
    
    return new;
  end if;
  if new."state" is not distinct from old."state" then
    return new;
  end if;
  if not (case old."state"::text when 'triage' then new."state"::text = any ('{backlog,unstarted,started,completed,canceled}'::text[]) when 'backlog' then new."state"::text = any ('{triage,unstarted,started,completed,canceled}'::text[]) when 'unstarted' then new."state"::text = any ('{triage,backlog,started,completed,canceled}'::text[]) when 'started' then new."state"::text = any ('{triage,backlog,unstarted,completed,canceled}'::text[]) when 'completed' then new."state"::text = any ('{triage,backlog,unstarted,started,canceled}'::text[]) when 'canceled' then new."state"::text = any ('{triage,backlog,unstarted,started,completed}'::text[]) else false end) then
    raise exception 'that status change is not allowed' using errcode = '22023', hint = 'STATE_TRANSITION_INVALID';
  end if;
  insert into "better_supabase"."status_history" ("tenant_id", "subject_type", "subject_id", "from_status", "to_status", "actor_id", "reason", "actor_name", "actor_email", "ip_address", "user_agent")
        values (new."tenant_id", 'work_item', new."id"::text, old."state"::text, new."state"::text, coalesce(auth.uid(), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'id', '')::uuid), nullif(current_setting('better_supabase.transition_reason', true), ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'name', ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'email', ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'ip', '')::inet, nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'userAgent', ''));
  
  perform "better_supabase".emit_event('status.changed', jsonb_build_object('organizationId', new."tenant_id"::text, 'subjectType', 'work_item', 'subjectId', new."id"::text, 'from', old."state"::text, 'to', new."state"::text, 'reason', nullif(current_setting('better_supabase.transition_reason', true), '')), 'statuses/work_item/' || new."id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/state-machine');
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.calibrate_appraisal (
  appraisal_id uuid,
  rating       integer,
  reason       text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."appraisals";
  v_cycle "better_supabase"."appraisal_cycles";
  v_reason text := nullif(trim(calibrate_appraisal.reason), '');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."appraisals" x where x."id" = calibrate_appraisal.appraisal_id for update;
  if not found then
    raise exception 'no such appraisal' using errcode = 'P0002', hint = 'APPRAISALS_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'appraisals.manage'), false))) then
    raise exception 'not allowed to calibrate appraisals' using errcode = '42501', hint = 'APPRAISALS_FORBIDDEN';
  end if;
  select * into v_cycle from "better_supabase"."appraisal_cycles" x where x."id" = v_row."cycle_id";
  if v_cycle."status" <> 'open' or v_row."status" not in ('reviewed', 'calibrated') then
    raise exception 'only a reviewed appraisal in an open cycle is calibrated' using errcode = '55000', hint = 'APPRAISALS_STATE';
  end if;
  if calibrate_appraisal.rating is null or calibrate_appraisal.rating not between 1 and 5 then
    raise exception 'the rating is a whole number from 1 to 5' using errcode = '22023', hint = 'APPRAISALS_INVALID';
  end if;
  if v_reason is null or length(v_reason) > 2000 then
    raise exception 'a calibration needs a reason of up to 2000 characters' using errcode = '22023', hint = 'APPRAISALS_INVALID';
  end if;
  insert into "better_supabase"."appraisal_calibrations" ("tenant_id", "appraisal_id", "from_rating", "to_rating", "reason", "calibrated_by")
  values (v_row."tenant_id", v_row."id", coalesce(v_row."calibrated_rating"::numeric, v_row."rating"), calibrate_appraisal.rating, v_reason, auth.uid());
  update "better_supabase"."appraisals" x
  set "calibrated_rating" = calibrate_appraisal.rating, "status" = 'calibrated', "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('appraisal.calibrated', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'cycleId', v_row."cycle_id", 'subjectUserId', v_row."appraisee_id", 'status', v_row."status", 'rating', v_row."calibrated_rating"), 'appraisals/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/appraisals');
  perform better_supabase.audit_event(
    event_type => 'appraisal.calibrated',
    category => 'data',
    target_type => 'appraisal',
    record_id => v_row."id"::text,
    summary => 'appraisal calibrated',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'cycleId', v_row."cycle_id", 'subjectUserId', v_row."appraisee_id", 'status', v_row."status", 'rating', v_row."calibrated_rating")
  );
  perform "better_supabase"."appraisal_step"(v_row."id", 'calibration');
  return "better_supabase"."appraisal_json"(v_row."id", true);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.calibrate_appraisal_competencies (
  appraisal_id uuid,
  competencies jsonb,
  reason       text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."appraisals";
  v_cycle "better_supabase"."appraisal_cycles";
  v_reason text := nullif(trim(calibrate_appraisal_competencies.reason), '');
  v_item record;
  v_merged jsonb;
  v_rating numeric;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."appraisals" x where x."id" = calibrate_appraisal_competencies.appraisal_id for update;
  if not found then
    raise exception 'no such appraisal' using errcode = 'P0002', hint = 'APPRAISALS_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'appraisals.manage'), false))) then
    raise exception 'not allowed to calibrate appraisals' using errcode = '42501', hint = 'APPRAISALS_FORBIDDEN';
  end if;
  select * into v_cycle from "better_supabase"."appraisal_cycles" x where x."id" = v_row."cycle_id";
  if v_cycle."status" <> 'open' or v_row."status" not in ('reviewed', 'calibrated') then
    raise exception 'only a reviewed appraisal in an open cycle is calibrated' using errcode = '55000', hint = 'APPRAISALS_STATE';
  end if;
  if jsonb_typeof(calibrate_appraisal_competencies.competencies) is distinct from 'object'
    or calibrate_appraisal_competencies.competencies = '{}'::jsonb then
    raise exception 'competencies is an object of competency ratings' using errcode = '22023', hint = 'APPRAISALS_INVALID';
  end if;
  if v_reason is null or length(v_reason) > 2000 then
    raise exception 'a calibration needs a reason of up to 2000 characters' using errcode = '22023', hint = 'APPRAISALS_INVALID';
  end if;
  for v_item in select e.key, e.value from jsonb_each(calibrate_appraisal_competencies.competencies) e loop
    if not exists (select 1 from "better_supabase"."appraisal_competencies" w where w."cycle_id" = v_cycle."id" and w."key" = v_item.key) then
      raise exception 'no such competency in this cycle''s rubric' using errcode = '22023', hint = 'APPRAISALS_INVALID';
    end if;
    if jsonb_typeof(v_item.value) <> 'number' or v_item.value::text !~ '^[1-5]$' then
      raise exception 'a competency rating is a whole number from 1 to 5' using errcode = '22023', hint = 'APPRAISALS_INVALID';
    end if;
  end loop;
  v_merged := v_row."calibrated_competencies" || calibrate_appraisal_competencies.competencies;
  v_rating := "better_supabase"."appraisal_score"(v_row."id", v_merged);
  insert into "better_supabase"."appraisal_calibrations" ("tenant_id", "appraisal_id", "from_rating", "to_rating", "competency_ratings", "reason", "calibrated_by")
  values (v_row."tenant_id", v_row."id", coalesce(v_row."calibrated_rating"::numeric, v_row."rating"), round(v_rating)::integer,
    calibrate_appraisal_competencies.competencies, v_reason, auth.uid());
  update "better_supabase"."appraisals" x
  set "calibrated_competencies" = v_merged, "calibrated_rating" = round(v_rating)::integer,
    "status" = 'calibrated', "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('appraisal.calibrated', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'cycleId', v_row."cycle_id", 'subjectUserId', v_row."appraisee_id", 'status', v_row."status", 'rating', v_row."calibrated_rating"), 'appraisals/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/appraisals');
  perform better_supabase.audit_event(
    event_type => 'appraisal.calibrated',
    category => 'data',
    target_type => 'appraisal',
    record_id => v_row."id"::text,
    summary => 'appraisal calibrated',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'cycleId', v_row."cycle_id", 'subjectUserId', v_row."appraisee_id", 'status', v_row."status", 'rating', v_row."calibrated_rating")
  );
  perform "better_supabase"."appraisal_step"(v_row."id", 'calibration');
  return "better_supabase"."appraisal_json"(v_row."id", true);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.cancel_booking_series (
  booking uuid,
  scope   text DEFAULT 'following'::text,
  reason  text DEFAULT NULL::text
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_booking "better_supabase"."bookings"%rowtype;
  v_id uuid;
  v_count integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_booking from "better_supabase"."bookings" bk where bk."id" = cancel_booking_series.booking;
  if not found or not ((auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_booking."tenant_id", 'bookings.manage'), false)) or (coalesce(v_booking."customer_id" = auth.uid(), false) and (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_booking."tenant_id", 'bookings.create'), false)))) then
    raise exception 'booking not found' using errcode = 'P0002', hint = 'BOOKING_NOT_FOUND';
  end if;
  if cancel_booking_series.scope is null or cancel_booking_series.scope not in ('one', 'following') then
    raise exception 'scope is one or following' using errcode = '22023', hint = 'BOOKING_SCOPE_INVALID';
  end if;
  for v_id in
    select bk."id" from "better_supabase"."bookings" bk
    where bk."status" <> 'cancelled'
      and (bk."id" = v_booking."id"
        or (cancel_booking_series.scope = 'following' and bk."series_id" = v_booking."series_id"
          and lower(bk."during") >= lower(v_booking."during")))
    order by lower(bk."during")
  loop
    perform "better_supabase"."change_booking"(v_id, 'cancelled', cancel_booking_series.reason, null);
    v_count := v_count + 1;
  end loop;
  if cancel_booking_series.scope = 'following' and v_booking."series_id" is not null then
    update "better_supabase"."booking_series" sr set
      "status" = case when exists (
        select 1 from "better_supabase"."bookings" bk where bk."series_id" = sr."id" and bk."status" <> 'cancelled'
      ) then 'ended' else 'cancelled' end,
      "ends_at" = (select max(upper(bk."during")) from "better_supabase"."bookings" bk where bk."series_id" = sr."id" and bk."status" <> 'cancelled'),
      "updated_at" = now()
    where sr."id" = v_booking."series_id";
  end if;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.change_booking (
  booking      uuid,
  to_status    text,
  reason       text,
  access_token text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_booking "better_supabase"."bookings"%rowtype;
  v_id uuid := change_booking.booking;
  v_calendar uuid;
  v_tz text;
  v_title text;
  v_event uuid;
begin
  select * into v_booking from "better_supabase"."bookings" bk where bk."id" = v_id for update;
  if not found then
    raise exception 'booking not found' using errcode = 'P0002', hint = 'BOOKING_NOT_FOUND';
  end if;
  if not (
    (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_booking."tenant_id", 'bookings.manage'), false))
    or (change_booking.access_token is not null and v_booking."access_hash" = encode(extensions.digest(convert_to(change_booking.access_token, 'utf8'), 'sha256'), 'hex'))
    or (change_booking.access_token is null and coalesce(v_booking."customer_id" = auth.uid(), false) and (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_booking."tenant_id", 'bookings.create'), false)))
  ) then
    raise exception 'not allowed to change this booking' using errcode = '42501', hint = 'BOOKING_FORBIDDEN';
  end if;
  if change_booking.to_status = 'confirmed' then
    if v_booking."status" = 'confirmed' then
      return jsonb_build_object('id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id", 'seat', v_booking."seat", 'startsAt', lower(v_booking."during"), 'endsAt', upper(v_booking."during"), 'status', v_booking."status", 'holdExpiresAt', v_booking."hold_expires_at", 'customerName', v_booking."customer_name", 'customerEmail', v_booking."customer_email", 'customerUserId', v_booking."customer_id", 'notes', v_booking."notes", 'seriesId', v_booking."series_id", 'createdAt', v_booking."created_at", 'cancelledAt', v_booking."cancelled_at", 'cancelReason', v_booking."cancel_reason");
    end if;
    if v_booking."status" <> 'hold' or v_booking."hold_expires_at" <= now() then
      raise exception 'the hold has expired or was cancelled' using errcode = '22023', hint = 'BOOKING_HOLD_EXPIRED';
    end if;
    update "better_supabase"."bookings" bk set "status" = 'confirmed', "hold_expires_at" = null, "updated_at" = now()
    where bk."id" = v_id returning * into v_booking;
    select r."calendar_id", r."tz", sv."name" into v_calendar, v_tz, v_title
  from "better_supabase"."booking_resources" r join "better_supabase"."booking_services" sv on sv."id" = v_booking."service_id"
  where r."id" = v_booking."resource_id";
  if v_calendar is not null then
    insert into "better_supabase"."calendar_events" ("tenant_id", "calendar_id", "uid", "title", "starts_at", "ends_at", "tz", "status", "subject_type", "subject_id")
    values (v_booking."tenant_id", v_calendar, 'booking-' || v_booking."id"::text, coalesce(v_booking."customer_name", v_title), lower(v_booking."during"), upper(v_booking."during"), v_tz, 'confirmed', 'booking', v_booking."id"::text)
    on conflict ("calendar_id", "uid", "original_starts_at") do update set "starts_at" = excluded."starts_at", "ends_at" = excluded."ends_at"
    returning "id" into v_event;
    update "better_supabase"."bookings" set "calendar_event_id" = v_event where "id" = v_booking."id";
  end if;
    delete from "better_supabase"."reminders" where "subject_type" = 'booking' and "subject_id" = v_booking."id"::text;
  delete from "better_supabase"."recurrence_rules" where "subject_type" = 'booking' and "subject_id" = v_booking."id"::text;
  insert into "better_supabase"."recurrence_rules" ("tenant_id", "subject_type", "subject_id", "dtstart", "tzid", "rrule")
  select v_booking."tenant_id", 'booking', v_booking."id"::text, lower(v_booking."during"), r."tz", 'FREQ=DAILY;COUNT=1'
  from "better_supabase"."booking_resources" r where r."id" = v_booking."resource_id";
  insert into "better_supabase"."reminders" ("tenant_id", "subject_type", "subject_id", "user_id", "offset_minutes")
  select v_booking."tenant_id", 'booking', v_booking."id"::text, v_booking."customer_id", o
  from "better_supabase"."booking_services" sv, unnest(sv."reminder_offsets") o
  where sv."id" = v_booking."service_id";
    perform "better_supabase".emit_event('booking.confirmed', jsonb_build_object('organizationId', v_booking."tenant_id", 'id', v_id, 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id"), 'bookings/' || v_id::text, (v_booking."tenant_id")::text, null, 'better-supabase/bookings');
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_booking_confirm"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  elsif change_booking.to_status = 'cancelled' then
    if v_booking."status" = 'cancelled' then
      return jsonb_build_object('id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id", 'seat', v_booking."seat", 'startsAt', lower(v_booking."during"), 'endsAt', upper(v_booking."during"), 'status', v_booking."status", 'holdExpiresAt', v_booking."hold_expires_at", 'customerName', v_booking."customer_name", 'customerEmail', v_booking."customer_email", 'customerUserId', v_booking."customer_id", 'notes', v_booking."notes", 'seriesId', v_booking."series_id", 'createdAt', v_booking."created_at", 'cancelledAt', v_booking."cancelled_at", 'cancelReason', v_booking."cancel_reason");
    end if;
    update "better_supabase"."bookings" bk set "status" = 'cancelled', "hold_expires_at" = null, "cancelled_at" = now(), "cancel_reason" = change_booking.reason, "updated_at" = now()
    where bk."id" = v_id returning * into v_booking;
    if v_booking."calendar_event_id" is not null then
    delete from "better_supabase"."calendar_events" where "id" = v_booking."calendar_event_id";
  end if;
    delete from "better_supabase"."reminders" where "subject_type" = 'booking' and "subject_id" = v_booking."id"::text;
  delete from "better_supabase"."recurrence_rules" where "subject_type" = 'booking' and "subject_id" = v_booking."id"::text;
    perform "better_supabase".emit_event('booking.cancelled', jsonb_build_object('organizationId', v_booking."tenant_id", 'id', v_id, 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id"), 'bookings/' || v_id::text, (v_booking."tenant_id")::text, null, 'better-supabase/bookings');
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_booking_cancel"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  else
    raise exception 'change a booking to confirmed or cancelled' using errcode = '22023', hint = 'BOOKING_STATUS_INVALID';
  end if;
  return jsonb_build_object('id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id", 'seat', v_booking."seat", 'startsAt', lower(v_booking."during"), 'endsAt', upper(v_booking."during"), 'status', v_booking."status", 'holdExpiresAt', v_booking."hold_expires_at", 'customerName', v_booking."customer_name", 'customerEmail', v_booking."customer_email", 'customerUserId', v_booking."customer_id", 'notes', v_booking."notes", 'seriesId', v_booking."series_id", 'createdAt', v_booking."created_at", 'cancelledAt', v_booking."cancelled_at", 'cancelReason', v_booking."cancel_reason");
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
    when now() < v_pass."starts_at" then 'not_yet_valid'
    when v_pass."expires_at" is not null and now() >= v_pass."expires_at" then 'expired'
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
    perform "better_supabase".emit_event('pass.admitted', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."pass_id", 'checkInId', v_row."id", 'resourceId', v_row."resource_id", 'bookingId', v_row."booking_id"), 'passes/' || v_row."pass_id"::text, (v_row."tenant_id")::text, null, 'better-supabase/passes');
  else
    perform "better_supabase".emit_event('pass.rejected', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."pass_id", 'checkInId', v_row."id", 'resourceId', v_row."resource_id", 'bookingId', v_row."booking_id", 'reason', v_row."reason"), 'passes/' || v_row."pass_id"::text, (v_row."tenant_id")::text, null, 'better-supabase/passes');
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id"::text, 'passId', v_row."pass_id", 'resourceId', v_row."resource_id", 'bookingId', v_row."booking_id", 'gate', v_row."gate", 'method', v_row."method", 'admitted', v_row."admitted", 'reason', v_row."reason", 'checkedInBy', v_row."checked_in_by", 'createdAt', v_row."created_at") || jsonb_build_object('pass', jsonb_build_object('id', v_pass."id", 'organizationId', v_pass."tenant_id"::text, 'kind', v_pass."kind", 'holderUserId', v_pass."holder_id", 'holderName', v_pass."holder_name", 'holderEmail', v_pass."holder_email", 'subjectType', v_pass."subject_type", 'subjectId', v_pass."subject_id", 'bookingId', v_pass."booking_id", 'resourceId', v_pass."resource_id", 'usesAllowed', v_pass."uses_allowed", 'uses', v_pass."uses", 'validFrom', v_pass."starts_at", 'validUntil', v_pass."expires_at", 'status', v_pass."status", 'issuedBy', v_pass."issued_by", 'createdAt', v_pass."created_at", 'updatedAt', v_pass."updated_at", 'revokedAt', v_pass."revoked_at"));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.close_deal (
  deal    uuid,
  outcome text,
  reason  text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."deals";
  v_stage uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."deals" x where x."id" = close_deal.deal and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.write'), false) and (true or coalesce(x."owner_id" = auth.uid(), false)
      or coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.manage'), false)
      or exists (select 1 from "better_supabase"."deal_members" mm where mm."deal_id" = x."id" and mm."user_id" = auth.uid()))));
  if v_row."id" is null then
    raise exception 'no such deal you can edit' using errcode = 'P0002', hint = 'DEAL_NOT_FOUND';
  end if;
  if close_deal.outcome not in ('won', 'lost') then
    raise exception 'close a deal as won or lost' using errcode = '22023', hint = 'DEAL_OUTCOME_INVALID';
  end if;
  select st."id" into v_stage from "better_supabase"."pipeline_stages" st
  where st."pipeline_id" = v_row."pipeline_id" and st."archived_at" is null
    and st."outcome" = case close_deal.outcome when 'won' then 'success' else 'failure' end
  order by st."rank" collate "C" limit 1;
  if v_stage is null then
    raise exception 'the pipeline has no stage for that outcome' using errcode = 'P0002', hint = 'DEAL_STAGE_MISSING';
  end if;
  update "better_supabase"."deals" x set "stage_id" = v_stage,
    "lost_reason" = case when close_deal.outcome = 'lost' then nullif(trim(close_deal.reason), '') end,
    "note" = case when close_deal.outcome = 'won' then coalesce(nullif(trim(close_deal.reason), ''), x."note") else x."note" end
  where x."id" = close_deal.deal;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text, 'amount', x."amount"::text, 'existing_amount', x."existing_amount"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text) || jsonb_build_object(
      'contacts', coalesce((select jsonb_agg(jsonb_build_object('type', ck."contact_type", 'id', ck."contact_id", 'role', ck."role", 'primary', ck."is_primary") order by ck."is_primary" desc, ck."contact_id") from "better_supabase"."deal_contacts" ck where ck."deal_id" = x."id"), '[]'::jsonb),
      'members', coalesce((select jsonb_agg(jsonb_build_object('userId', cm."user_id", 'role', cm."role") order by cm."user_id") from "better_supabase"."deal_members" cm where cm."deal_id" = x."id"), '[]'::jsonb)) from "better_supabase"."deals" x where x."id" = close_deal.deal);
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
  v_subjects jsonb := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = complete_activity.engagement), '[]'::jsonb);
  v_first jsonb := v_subjects -> 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if exists (select 1 from "better_supabase"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the engagement is locked: add an addendum with amend_activity instead' using errcode = '55000', hint = 'ACTIVITY_LOCKED';
  end if;
  update "better_supabase"."activities" x set
    "done_at" = case when complete_activity.done then coalesce(x."done_at", now()) end,
    "outcome" = coalesce(complete_activity.outcome, x."outcome"),
    "updated_at" = now()
  where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false))
  returning x."tenant_id", x."type" into v_tenant, v_type;
  if v_tenant is null then
    raise exception 'no such engagement you can edit' using errcode = 'P0002', hint = 'ACTIVITY_NOT_FOUND';
  end if;
  if complete_activity.done then
    perform "better_supabase".emit_event('activity.completed', jsonb_build_object('organizationId', v_tenant, 'engagementId', v_id, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects), 'engagements/' || v_id::text, (v_tenant::text)::text, null, 'better-supabase/activities');
  end if;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."activities" x where x."id" = v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_deal (
  tenant   uuid,
  attrs    jsonb,
  contacts jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_deal uuid;
  v_seq bigint;
  v_identifier text;
  v_row "better_supabase"."deals";
  v_company_type text := coalesce(create_deal.attrs -> 'company' ->> 'type', 'company');
  v_company_id text := create_deal.attrs -> 'company' ->> 'id';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', create_deal.tenant, 'deals.write'), false)) then
    raise exception 'not allowed to change deals' using errcode = '42501', hint = 'DEAL_FORBIDDEN';
  end if;
  if nullif(trim(create_deal.attrs ->> 'name'), '') is null or (create_deal.attrs ->> 'closeOn') is null then
    raise exception 'a deal needs a name and a close date' using errcode = '23502', hint = 'DEAL_ATTRS_INVALID';
  end if;
  if v_company_id is not null and not (case v_company_type
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'rfq' then exists (select 1 from "better_supabase"."rfqs" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'till' then exists (select 1 from "better_supabase"."tills" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'meeting' then exists (select 1 from "better_supabase"."meetings" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'meeting_decision' then exists (select 1 from "better_supabase"."meeting_decisions" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'maintenance_plan' then exists (select 1 from "better_supabase"."maintenance_plans" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'dam_usage_right' then exists (select 1 from "better_supabase"."dam_usage_rights" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'lims_sample' then exists (select 1 from "better_supabase"."lims_samples" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = create_deal.tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = create_deal.tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = create_deal.tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = create_deal.tenant::text)
      else false
    end and "better_supabase"."can_subject"(v_company_type, v_company_id, 'read')) then
    raise exception 'the company is unknown or not readable in this organization' using errcode = '42501', hint = 'DEAL_COMPANY_FORBIDDEN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_deal_create"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using create_deal.tenant, create_deal.attrs;
    end if;
  end;
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'deal' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_identifier := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'deal' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    if better_supabase.import_run() is null then
      raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
    end if;
    v_seq := coalesce(substring(v_identifier from '([0-9]+)$')::bigint, 0);
    perform set_config('better_supabase.fixed_number', '', true);
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(create_deal.tenant::text || ':deal', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from "better_supabase"."deals" x where x."tenant_id" = create_deal.tenant;
  v_identifier := 'DEAL-' || v_seq::text;
  end if;
  begin
    insert into "better_supabase"."deals" ("tenant_id", "number", "identifier", "name", "company_type", "company_id", "owner_id", "motion", "priority", "product", "seats", "amount", "existing_amount", "currency", "value_period", "pipeline_id", "stage_id", "probability", "forecast_category", "expected_close_on", "next_step", "next_at", "next_kind", "flags", "source", "note", "created_by")
    values (create_deal.tenant,
      v_seq,
      v_identifier,
      trim(create_deal.attrs ->> 'name'),
      case when v_company_id is null then null else v_company_type end,
      v_company_id,
      coalesce((create_deal.attrs ->> 'ownerId')::uuid, auth.uid()),
      create_deal.attrs ->> 'motion',
      create_deal.attrs ->> 'priority',
      create_deal.attrs ->> 'product',
      (create_deal.attrs ->> 'seats')::integer,
      coalesce((create_deal.attrs ->> 'amount')::bigint, 0),
      coalesce((create_deal.attrs ->> 'existingAmount')::bigint, 0),
      upper(coalesce(create_deal.attrs ->> 'currency', 'EUR')),
      coalesce(create_deal.attrs ->> 'valuePeriod', 'one_time'),
      (create_deal.attrs ->> 'pipelineId')::uuid,
      (create_deal.attrs ->> 'stageId')::uuid,
      (create_deal.attrs ->> 'probability')::smallint,
      create_deal.attrs ->> 'forecast',
      (create_deal.attrs ->> 'closeOn')::date,
      create_deal.attrs ->> 'nextStep',
      (create_deal.attrs ->> 'nextAt')::timestamptz,
      create_deal.attrs ->> 'nextKind',
      coalesce(array(select jsonb_array_elements_text(case jsonb_typeof(create_deal.attrs -> 'flags') when 'array' then create_deal.attrs -> 'flags' else '[]' end)), '{}'),
      create_deal.attrs ->> 'source',
      create_deal.attrs ->> 'note',
      auth.uid())
    returning * into v_row;
  exception when check_violation or invalid_text_representation or datetime_field_overflow or numeric_value_out_of_range then
    raise exception 'a deal field has an invalid value' using errcode = '22023', hint = 'DEAL_ATTRS_INVALID';
  end;
  v_deal := v_row."id";
  if v_row."motion" is not null and not (v_row."motion" = any ('{new_logo,expansion,renewal}'::text[])) then
    raise exception 'unknown motion' using errcode = '22023', hint = 'DEAL_MOTION_INVALID';
  end if;
  if v_row."priority" is not null and not (v_row."priority" = any ('{hot,warm,cold}'::text[])) then
    raise exception 'unknown priority' using errcode = '22023', hint = 'DEAL_PRIORITY_INVALID';
  end if;
  if create_deal.contacts is not null then
    perform "better_supabase"."set_deal_contacts"(v_deal, create_deal.contacts);
  end if;
  perform "better_supabase".emit_event('deal.created', jsonb_build_object('organizationId', create_deal.tenant, 'dealId', v_deal, 'subjectType', 'deal', 'subjectId', v_deal::text, 'name', v_row."name"), 'deals/' || v_deal::text, (create_deal.tenant::text)::text, null, 'better-supabase/deals');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_deal_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_deal;
    end if;
  end;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text, 'amount', x."amount"::text, 'existing_amount', x."existing_amount"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text) || jsonb_build_object(
      'contacts', coalesce((select jsonb_agg(jsonb_build_object('type', ck."contact_type", 'id', ck."contact_id", 'role', ck."role", 'primary', ck."is_primary") order by ck."is_primary" desc, ck."contact_id") from "better_supabase"."deal_contacts" ck where ck."deal_id" = x."id"), '[]'::jsonb),
      'members', coalesce((select jsonb_agg(jsonb_build_object('userId', cm."user_id", 'role', cm."role") order by cm."user_id") from "better_supabase"."deal_members" cm where cm."deal_id" = x."id"), '[]'::jsonb)) from "better_supabase"."deals" x where x."id" = v_deal);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_quote (
  tenant uuid,
  attrs  jsonb,
  lines  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_seq bigint;
  v_identifier text;
  v_row "better_supabase"."quotes";
  v_company_type text := coalesce(create_quote.attrs -> 'company' ->> 'type', 'company');
  v_company_id text := create_quote.attrs -> 'company' ->> 'id';
  v_contact_type text := coalesce(create_quote.attrs -> 'contact' ->> 'type', 'person');
  v_contact_id text := create_quote.attrs -> 'contact' ->> 'id';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', create_quote.tenant, 'quotes.write'), false)) then
    raise exception 'not allowed to change quotes' using errcode = '42501', hint = 'QUOTE_FORBIDDEN';
  end if;
  if nullif(trim(create_quote.attrs ->> 'title'), '') is null then
    raise exception 'a quote needs a title' using errcode = '23502', hint = 'QUOTE_ATTRS_INVALID';
  end if;
  if v_company_id is not null and not (case v_company_type
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'rfq' then exists (select 1 from "better_supabase"."rfqs" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'till' then exists (select 1 from "better_supabase"."tills" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'meeting' then exists (select 1 from "better_supabase"."meetings" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'meeting_decision' then exists (select 1 from "better_supabase"."meeting_decisions" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'maintenance_plan' then exists (select 1 from "better_supabase"."maintenance_plans" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'dam_usage_right' then exists (select 1 from "better_supabase"."dam_usage_rights" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'lims_sample' then exists (select 1 from "better_supabase"."lims_samples" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = create_quote.tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = create_quote.tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = create_quote.tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = create_quote.tenant::text)
      else false
    end and "better_supabase"."can_subject"(v_company_type, v_company_id, 'read')) then
    raise exception 'the company is unknown or not readable in this organization' using errcode = '42501', hint = 'QUOTE_COMPANY_FORBIDDEN';
  end if;
  if v_contact_id is not null and not (case v_contact_type
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'rfq' then exists (select 1 from "better_supabase"."rfqs" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'till' then exists (select 1 from "better_supabase"."tills" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'meeting' then exists (select 1 from "better_supabase"."meetings" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'meeting_decision' then exists (select 1 from "better_supabase"."meeting_decisions" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'maintenance_plan' then exists (select 1 from "better_supabase"."maintenance_plans" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'dam_usage_right' then exists (select 1 from "better_supabase"."dam_usage_rights" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'lims_sample' then exists (select 1 from "better_supabase"."lims_samples" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_contact_id)::uuid and s."organization_id"::text = create_quote.tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (v_contact_id)::uuid and s."organization_id"::text = create_quote.tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_contact_id)::uuid and s."organization_id"::text = create_quote.tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_contact_id)::uuid and s."organization_id"::text = create_quote.tenant::text)
      else false
    end and "better_supabase"."can_subject"(v_contact_type, v_contact_id, 'read')) then
    raise exception 'the contact is unknown or not readable in this organization' using errcode = '42501', hint = 'QUOTE_CONTACT_FORBIDDEN';
  end if;
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'quote' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_identifier := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'quote' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    if better_supabase.import_run() is null then
      raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
    end if;
    v_seq := coalesce(substring(v_identifier from '([0-9]+)$')::bigint, 0);
    perform set_config('better_supabase.fixed_number', '', true);
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(create_quote.tenant::text || ':quote', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from "better_supabase"."quotes" x where x."tenant_id" = create_quote.tenant;
  v_identifier := 'Q-' || v_seq::text;
  end if;
  begin
    insert into "better_supabase"."quotes" ("tenant_id", "number", "identifier", "title", "company_type", "company_id", "contact_type", "contact_id",
      "owner_id", "currency", "valid_until", "terms", "note", "origin_type", "origin_id", "prices_include_tax", "discount_bps", "discount_amount", "deposit_bps", "deposit_amount", "deposit_required", "created_by")
    values (create_quote.tenant, v_seq, v_identifier, trim(create_quote.attrs ->> 'title'),
      case when v_company_id is null then null else v_company_type end, v_company_id,
      case when v_contact_id is null then null else v_contact_type end, v_contact_id,
      coalesce((create_quote.attrs ->> 'ownerId')::uuid, auth.uid()), upper(coalesce(create_quote.attrs ->> 'currency', 'EUR')),
      coalesce((create_quote.attrs ->> 'validUntil')::date, current_date + 30),
      create_quote.attrs ->> 'terms', create_quote.attrs ->> 'note',
      create_quote.attrs -> 'origin' ->> 'type', create_quote.attrs -> 'origin' ->> 'id',
      coalesce((create_quote.attrs ->> 'pricesIncludeTax')::boolean, false), coalesce((create_quote.attrs ->> 'discountBps')::integer, 0), coalesce((create_quote.attrs ->> 'discountAmount')::bigint, 0), (create_quote.attrs ->> 'depositBps')::integer, (create_quote.attrs ->> 'depositAmount')::bigint, coalesce((create_quote.attrs ->> 'depositRequired')::boolean, false), auth.uid())
    returning * into v_row;
  exception when check_violation or invalid_text_representation or datetime_field_overflow or numeric_value_out_of_range then
    raise exception 'a quote field has an invalid value' using errcode = '22023', hint = 'QUOTE_ATTRS_INVALID';
  end;
  if v_row."deposit_bps" is not null and v_row."deposit_amount" is not null then
    raise exception 'a deposit is a share (depositBps) or an amount (depositAmount), not both' using errcode = '22023', hint = 'QUOTE_ATTRS_INVALID';
  end if;
  if create_quote.lines is not null then
    perform "better_supabase"."set_quote_lines"(v_row."id", create_quote.lines);
  end if;
  if v_row."origin_id" is not null then
    insert into "better_supabase"."relations" ("tenant_id", "kind", "source_type", "source_id", "target_type", "target_id", "created_by")
    select v_row."tenant_id", 'created_from', 'quote', v_row."id"::text, v_row."origin_type", v_row."origin_id", auth.uid()
    where not exists (
      select 1 from "better_supabase"."relations" x
      where x."kind" = 'created_from' and x."source_type" = 'quote' and x."source_id" = v_row."id"::text
    );
  end if;
  perform "better_supabase".emit_event('quote.created', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier"), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
  return (select (to_jsonb(x) - 'token_hash') || jsonb_build_object('number', x."number"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text, 'discount_amount', x."discount_amount"::text, 'deposit_due', x."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'unit', ql."unit", 'discountKind', ql."discount_kind", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = x."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = x."id"), '[]'::jsonb)) from "better_supabase"."quotes" x where x."id" = v_row."id");
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
    ('user', 'better_supabase.notification_digests', '"better_supabase"."notification_digests"', 'user_id', true, '{}'::text[], true),
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
    ('user', 'better_supabase.ai_chat_links', '"better_supabase"."ai_chat_links"', 'created_by', true, array['salt']::text[], true),
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
    ('user', 'better_supabase.status_history', '"better_supabase"."status_history"', 'actor_id', true, '{}'::text[], true),
    ('user', 'better_supabase.share_links', '"better_supabase"."share_links"', 'created_by', true, array['token_hash', 'password_hash']::text[], true),
    ('user', 'better_supabase.reminders', '"better_supabase"."reminders"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.import_runs', '"better_supabase"."import_runs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.subject_members', '"better_supabase"."subject_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.saved_view_preferences', '"better_supabase"."saved_view_preferences"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.bulk_runs', '"better_supabase"."bulk_runs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.calendar_events', '"better_supabase"."calendar_events"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.calendar_attendees', '"better_supabase"."calendar_attendees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.calendar_working_hours', '"better_supabase"."calendar_working_hours"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.bookings', '"better_supabase"."bookings"', 'customer_id', true, '{}'::text[], true),
    ('user', 'better_supabase.versions', '"better_supabase"."versions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.trash_items', '"better_supabase"."trash_items"', 'trashed_by', true, '{}'::text[], true),
    ('user', 'better_supabase.reactions', '"better_supabase"."reactions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.custom_emoji', '"better_supabase"."custom_emoji"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.approval_requests', '"better_supabase"."approval_requests"', 'requested_by', true, '{}'::text[], true),
    ('user', 'better_supabase.approval_decisions', '"better_supabase"."approval_decisions"', 'approver', true, '{}'::text[], true),
    ('user', 'better_supabase.approval_items', '"better_supabase"."approval_items"', 'decided_by', true, '{}'::text[], true),
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
    ('user', 'better_supabase.deals', '"better_supabase"."deals"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.deal_members', '"better_supabase"."deal_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.application_scorecards', '"better_supabase"."application_scorecards"', 'reviewer_id', true, '{}'::text[], true),
    ('user', 'better_supabase.work_items', '"better_supabase"."work_items"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.work_item_checklist_items', '"better_supabase"."work_item_checklist_items"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.work_item_assignees', '"better_supabase"."work_item_assignees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.pipeline_stage_history', '"better_supabase"."pipeline_stage_history"', 'actor_id', true, '{}'::text[], true),
    ('user', 'better_supabase.activities', '"better_supabase"."activities"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.quotes', '"better_supabase"."quotes"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.employees', '"better_supabase"."employees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.employee_private_details', '"better_supabase"."employee_private_details"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.moderation_reports', '"better_supabase"."moderation_reports"', 'reporter_id', true, '{}'::text[], true),
    ('user', 'better_supabase.moderation_bans', '"better_supabase"."moderation_bans"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.moderation_notices', '"better_supabase"."moderation_notices"', 'notifier_id', true, '{}'::text[], true),
    ('user', 'better_supabase.moderation_flaggers', '"better_supabase"."moderation_flaggers"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.moderation_appeals', '"better_supabase"."moderation_appeals"', 'appellant_id', true, '{}'::text[], true),
    ('user', 'better_supabase.assets', '"better_supabase"."assets"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.score_models', '"better_supabase"."score_models"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.score_model_versions', '"better_supabase"."score_model_versions"', 'saved_by', true, '{}'::text[], true),
    ('user', 'better_supabase.passes', '"better_supabase"."passes"', 'holder_id', true, '{}'::text[], true),
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
    ('user', 'better_supabase.incident_regulatory_filings', '"better_supabase"."incident_regulatory_filings"', 'submitted_by', true, '{}'::text[], true),
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
    ('user', 'better_supabase.shift_swaps', '"better_supabase"."shift_swaps"', 'from_id', true, '{}'::text[], true),
    ('user', 'better_supabase.shift_availability', '"better_supabase"."shift_availability"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.acknowledgements', '"better_supabase"."acknowledgements"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.acknowledgement_notices', '"better_supabase"."acknowledgement_notices"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.consent_signals', '"better_supabase"."consent_signals"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.observations', '"better_supabase"."observations"', 'performer_id', true, '{}'::text[], true),
    ('user', 'better_supabase.care_plan_evaluations', '"better_supabase"."care_plan_evaluations"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.inspection_members', '"better_supabase"."inspection_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.meeting_attendees', '"better_supabase"."meeting_attendees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.payroll_lines', '"better_supabase"."payroll_lines"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.maintenance_meter_readings', '"better_supabase"."maintenance_meter_readings"', 'read_by', true, '{}'::text[], true),
    ('user', 'better_supabase.maintenance_calibrations', '"better_supabase"."maintenance_calibrations"', 'performed_by', true, '{}'::text[], true),
    ('user', 'better_supabase.dam_usage_rights', '"better_supabase"."dam_usage_rights"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.lims_samples', '"better_supabase"."lims_samples"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.lims_results', '"better_supabase"."lims_results"', 'tested_by', true, '{}'::text[], true),
    ('user', 'better_supabase.appraisal_cycles', '"better_supabase"."appraisal_cycles"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.appraisals', '"better_supabase"."appraisals"', 'appraisee_id', true, '{}'::text[], true),
    ('user', 'better_supabase.appraisal_reviews', '"better_supabase"."appraisal_reviews"', 'reviewer_id', true, '{}'::text[], true),
    ('user', 'better_supabase.appraisal_calibrations', '"better_supabase"."appraisal_calibrations"', 'calibrated_by', true, '{}'::text[], true),
    ('user', 'better_supabase.pick_waves', '"better_supabase"."pick_waves"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.pick_lists', '"better_supabase"."pick_lists"', 'assignee_id', true, '{}'::text[], true),
    ('user', 'better_supabase.rfqs', '"better_supabase"."rfqs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.rfq_quotes', '"better_supabase"."rfq_quotes"', 'submitted_by', true, '{}'::text[], true),
    ('user', 'better_supabase.till_sessions', '"better_supabase"."till_sessions"', 'opened_by', true, '{}'::text[], true),
    ('user', 'better_supabase.till_movements', '"better_supabase"."till_movements"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.till_counts', '"better_supabase"."till_counts"', 'counted_by', true, '{}'::text[], true),
    ('user', 'better_supabase.till_deposits', '"better_supabase"."till_deposits"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.care_alerts', '"better_supabase"."care_alerts"', 'decided_by', true, '{}'::text[], true),
    ('user', 'better_supabase.periods', '"better_supabase"."periods"', 'closed_by', true, '{}'::text[], true),
    ('user', 'better_supabase.deadlines', '"better_supabase"."deadlines"', 'satisfied_by', true, '{}'::text[], true),
    ('user', 'better_supabase.commission_assignments', '"better_supabase"."commission_assignments"', 'seller_id', true, '{}'::text[], true),
    ('user', 'better_supabase.commissions', '"better_supabase"."commissions"', 'seller_id', true, '{}'::text[], true),
    ('user', 'better_supabase.commission_statements', '"better_supabase"."commission_statements"', 'seller_id', true, '{}'::text[], true),
    ('user', 'better_supabase.referral_codes', '"better_supabase"."referral_codes"', 'referrer_id', true, '{}'::text[], true),
    ('user', 'better_supabase.referrals', '"better_supabase"."referrals"', 'referrer_id', true, '{}'::text[], true),
    ('user', 'better_supabase.prescriptions', '"better_supabase"."prescriptions"', 'prescriber_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.notification_digests', '"better_supabase"."notification_digests"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.webhook_endpoints', '"better_supabase"."webhook_endpoints"', 'organization_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.webhook_endpoint_secrets', '"better_supabase"."webhook_endpoint_secrets"', 'organization_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.webhook_deliveries', '"better_supabase"."webhook_deliveries"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.api_keys', '"better_supabase"."api_keys"', 'organization_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.organization_settings', '"better_supabase"."organization_settings"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_counters', '"better_supabase"."usage_counters"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_events', '"better_supabase"."usage_events"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_history', '"better_supabase"."usage_history"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_distinct', '"better_supabase"."usage_distinct"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_billed_periods', '"better_supabase"."usage_billed_periods"', 'organization_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.attachment_document_types', '"better_supabase"."attachment_document_types"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.attachment_versions', '"better_supabase"."attachment_versions"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.retention_policies', '"better_supabase"."retention_policies"', 'organization_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.data_subject_requests', '"better_supabase"."data_subject_requests"', 'organization_id', true, '{}'::text[], false),
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
    ('organization', 'better_supabase.import_records', '"better_supabase"."import_records"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.product_identifiers', '"better_supabase"."product_identifiers"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_relations', '"better_supabase"."product_relations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.supplier_items', '"better_supabase"."supplier_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.supplier_item_mappings', '"better_supabase"."supplier_item_mappings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.discount_groups', '"better_supabase"."discount_groups"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.discount_group_parties', '"better_supabase"."discount_group_parties"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.discount_rules', '"better_supabase"."discount_rules"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.approval_items', '"better_supabase"."approval_items"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.purchase_requisitions', '"better_supabase"."purchase_requisitions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.purchase_requisition_lines', '"better_supabase"."purchase_requisition_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inventory_receipts', '"better_supabase"."inventory_receipts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inventory_receipt_lines', '"better_supabase"."inventory_receipt_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_items', '"better_supabase"."stock_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_bins', '"better_supabase"."stock_bins"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_lots', '"better_supabase"."stock_lots"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_serials', '"better_supabase"."stock_serials"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_buckets', '"better_supabase"."stock_buckets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_allocations', '"better_supabase"."stock_allocations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_counts', '"better_supabase"."stock_counts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_count_lines', '"better_supabase"."stock_count_lines"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.payment_terms', '"better_supabase"."payment_terms"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_delivery_preferences', '"better_supabase"."document_delivery_preferences"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.invoice_dunning_levels', '"better_supabase"."invoice_dunning_levels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_dunning_runs', '"better_supabase"."invoice_dunning_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_dunning_run_items', '"better_supabase"."invoice_dunning_run_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_dunning_history', '"better_supabase"."invoice_dunning_history"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_allocations', '"better_supabase"."invoice_allocations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_line_sources', '"better_supabase"."invoice_line_sources"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_approval_levels', '"better_supabase"."invoice_approval_levels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_approvals', '"better_supabase"."invoice_approvals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_e_endpoints', '"better_supabase"."invoice_e_endpoints"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.e_invoice_deliveries', '"better_supabase"."e_invoice_deliveries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sla_policies', '"better_supabase"."sla_policies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sla_escalations', '"better_supabase"."sla_escalations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sla_clocks', '"better_supabase"."sla_clocks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.goals', '"better_supabase"."goals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employees', '"better_supabase"."employees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employee_private_details', '"better_supabase"."employee_private_details"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employee_contracts', '"better_supabase"."employee_contracts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_items', '"better_supabase"."moderation_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_reports', '"better_supabase"."moderation_reports"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_actions', '"better_supabase"."moderation_actions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_bans', '"better_supabase"."moderation_bans"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_statements', '"better_supabase"."moderation_statements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_notices', '"better_supabase"."moderation_notices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_flaggers', '"better_supabase"."moderation_flaggers"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_appeals', '"better_supabase"."moderation_appeals"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.intrastat_lines', '"better_supabase"."intrastat_lines"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.incident_regulatory_profiles', '"better_supabase"."incident_regulatory_profiles"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_regulatory_filings', '"better_supabase"."incident_regulatory_filings"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.tax_codes', '"better_supabase"."tax_codes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.tax_rates', '"better_supabase"."tax_rates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_tax_lines', '"better_supabase"."invoice_tax_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.tax_returns', '"better_supabase"."tax_returns"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.eu_sales_list_lines', '"better_supabase"."eu_sales_list_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_recognition_schedules', '"better_supabase"."accounting_recognition_schedules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_recognition_rows', '"better_supabase"."accounting_recognition_rows"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.accounting_opening_balances', '"better_supabase"."accounting_opening_balances"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_budgets', '"better_supabase"."accounting_budgets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_budget_lines', '"better_supabase"."accounting_budget_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.acknowledgement_assignments', '"better_supabase"."acknowledgement_assignments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.acknowledgements', '"better_supabase"."acknowledgements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.acknowledgement_notices', '"better_supabase"."acknowledgement_notices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.consent_purposes', '"better_supabase"."consent_purposes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.consents', '"better_supabase"."consents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.consent_signals', '"better_supabase"."consent_signals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.consent_receipts', '"better_supabase"."consent_receipts"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.inspection_findings', '"better_supabase"."inspection_findings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.boms', '"better_supabase"."boms"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_centers', '"better_supabase"."work_centers"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bom_operations', '"better_supabase"."bom_operations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bom_components', '"better_supabase"."bom_components"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.production_orders', '"better_supabase"."production_orders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.production_order_operations', '"better_supabase"."production_order_operations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.production_consumptions', '"better_supabase"."production_consumptions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_lot_links', '"better_supabase"."stock_lot_links"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bank_accounts', '"better_supabase"."bank_accounts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bank_rules', '"better_supabase"."bank_rules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bank_statements', '"better_supabase"."bank_statements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bank_transactions', '"better_supabase"."bank_transactions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bank_matches', '"better_supabase"."bank_matches"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.payment_batches', '"better_supabase"."payment_batches"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.payment_batch_items', '"better_supabase"."payment_batch_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.meetings', '"better_supabase"."meetings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.meeting_attendees', '"better_supabase"."meeting_attendees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.meeting_agenda_items', '"better_supabase"."meeting_agenda_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.meeting_decisions', '"better_supabase"."meeting_decisions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.meeting_action_items', '"better_supabase"."meeting_action_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.legal_entities', '"better_supabase"."legal_entities"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.legal_entity_settings', '"better_supabase"."legal_entity_settings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.funding_products', '"better_supabase"."funding_products"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.funding_awards', '"better_supabase"."funding_awards"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.funding_deliveries', '"better_supabase"."funding_deliveries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.funding_claims', '"better_supabase"."funding_claims"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.funding_claim_lines', '"better_supabase"."funding_claim_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.payroll_runs', '"better_supabase"."payroll_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.payroll_lines', '"better_supabase"."payroll_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.maintenance_plans', '"better_supabase"."maintenance_plans"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.maintenance_plan_parts', '"better_supabase"."maintenance_plan_parts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.maintenance_meters', '"better_supabase"."maintenance_meters"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.maintenance_meter_readings', '"better_supabase"."maintenance_meter_readings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.maintenance_calibrations', '"better_supabase"."maintenance_calibrations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.dam_usage_rights', '"better_supabase"."dam_usage_rights"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.dam_renditions', '"better_supabase"."dam_renditions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_templates', '"better_supabase"."document_templates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_text_blocks', '"better_supabase"."document_text_blocks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rendered_documents', '"better_supabase"."rendered_documents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.lims_methods', '"better_supabase"."lims_methods"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.lims_samples', '"better_supabase"."lims_samples"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.lims_results', '"better_supabase"."lims_results"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.appraisal_cycles', '"better_supabase"."appraisal_cycles"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.appraisals', '"better_supabase"."appraisals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.appraisal_reviews', '"better_supabase"."appraisal_reviews"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.appraisal_calibrations', '"better_supabase"."appraisal_calibrations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.appraisal_competencies', '"better_supabase"."appraisal_competencies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.appraisal_review_ratings', '"better_supabase"."appraisal_review_ratings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.appraisal_goals', '"better_supabase"."appraisal_goals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pick_waves', '"better_supabase"."pick_waves"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pick_lists', '"better_supabase"."pick_lists"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pick_lines', '"better_supabase"."pick_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.count_plans', '"better_supabase"."count_plans"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.putaway_rules', '"better_supabase"."putaway_rules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bin_slots', '"better_supabase"."bin_slots"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.variant_sizes', '"better_supabase"."variant_sizes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rfqs', '"better_supabase"."rfqs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rfq_lines', '"better_supabase"."rfq_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rfq_suppliers', '"better_supabase"."rfq_suppliers"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rfq_quotes', '"better_supabase"."rfq_quotes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rfq_quote_lines', '"better_supabase"."rfq_quote_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.tills', '"better_supabase"."tills"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.till_sessions', '"better_supabase"."till_sessions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.till_movements', '"better_supabase"."till_movements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.till_counts', '"better_supabase"."till_counts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.till_deposits', '"better_supabase"."till_deposits"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.care_rules', '"better_supabase"."care_rules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.care_alerts', '"better_supabase"."care_alerts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.periods', '"better_supabase"."periods"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deadlines', '"better_supabase"."deadlines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.commission_plans', '"better_supabase"."commission_plans"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.commission_assignments', '"better_supabase"."commission_assignments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.commissions', '"better_supabase"."commissions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.commission_statements', '"better_supabase"."commission_statements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.referral_codes', '"better_supabase"."referral_codes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.referrals', '"better_supabase"."referrals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.prescriptions', '"better_supabase"."prescriptions"', 'tenant_id', true, '{}'::text[], true)
  ) as t(subject, name, tbl, col, purge, omit, exported)
  ) as t(subject, name, tbl, col, purge, omit, exported)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.deal_board (
  pipeline uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
begin
  return (with cards as (
    select x."stage_id" as stage_id,
      x."rank" as rank,
      x."id" as id,
      x."outcome" as outcome,
      x."currency"::text as currency,
      x."amount" as amount,
      coalesce(x."probability", st."probability") as prob,
      jsonb_build_object(
        'id', x."id", 'identifier', x."identifier", 'name', x."name",
        'amount', x."amount"::text, 'currency', x."currency"::text,
        'ownerId', x."owner_id", 'closeOn', x."expected_close_on",
        'probability', coalesce(x."probability", st."probability"),
        'daysInStage', (extract(epoch from now() - coalesce(x."stage_entered_at", x."created_at")) / 86400)::integer,
        'rotting', st."rotting_after_days" is not null and now() - coalesce(x."stage_entered_at", x."created_at") > make_interval(days => st."rotting_after_days"),
        'nextStep', x."next_step",
        'nextAt', x."next_at",
        'rank', x."rank"
      ) as card
    from "better_supabase"."deals" x
    left join "better_supabase"."pipeline_stages" st on st."id" = x."stage_id"
    where x."pipeline_id" = deal_board.pipeline and x."archived_at" is null
  )
  select jsonb_build_object(
    'pipelineId', deal_board.pipeline,
    'stages', coalesce((select jsonb_agg(jsonb_build_object(
      'id', st."id", 'key', st."key", 'name', st."name", 'category', st."category",
      'probability', st."probability",
      'rottingAfterDays', st."rotting_after_days",
      'wipLimit', st."wip_limit",
      'count', (select count(*) from cards c where c.stage_id = st."id"),
      'totals', coalesce((select jsonb_agg(jsonb_build_object('currency', t.currency, 'amount', t.amount::text, 'weighted', t.weighted::text) order by t.currency)
        from (select c.currency, sum(c.amount) as amount, round(sum(c.amount * coalesce(c.prob, 0) / 100.0))::bigint as weighted
          from cards c where c.stage_id = st."id" group by c.currency) t), '[]'::jsonb),
      'deals', coalesce((select jsonb_agg(c.card order by c.rank, c.id) from cards c where c.stage_id = st."id"), '[]'::jsonb)
    ) order by st."rank", st."id")
      from "better_supabase"."pipeline_stages" st
      where st."pipeline_id" = deal_board.pipeline and st."archived_at" is null), '[]'::jsonb),
    'weighted', coalesce((select jsonb_agg(jsonb_build_object('currency', t.currency, 'amount', t.amount::text) order by t.currency)
      from (select c.currency, round(sum(c.amount * coalesce(c.prob, 0) / 100.0))::bigint as amount
        from cards c where c.outcome = 'open' group by c.currency) t), '[]'::jsonb)
  ));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.deal_forecast (
  tenant   uuid,
  pipeline uuid,
  since    date,
  until    date,
  currency text,
  target   bigint,
  owner    uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  with scoped as (
    select * from "better_supabase"."deals" x
    where x."tenant_id" = deal_forecast.tenant
      and x."currency" = upper(deal_forecast.currency)
      and x."archived_at" is null
      and (deal_forecast.pipeline is null or x."pipeline_id" = deal_forecast.pipeline)
      and (deal_forecast.owner is null or x."owner_id" = deal_forecast.owner)
  ),
  totals as (
    select jsonb_build_object(
      'won', coalesce(sum(x."amount") filter (where x."outcome" = 'won' and x."closed_at"::date >= deal_forecast.since and x."closed_at"::date <= deal_forecast.until), 0)::text,
      'commit', coalesce(sum(x."amount") filter (where x."outcome" = 'open' and x."forecast_category" is distinct from 'omit' and x."expected_close_on" >= deal_forecast.since and x."expected_close_on" <= deal_forecast.until and x."forecast_category" = 'commit'), 0)::text,
      'bestCase', coalesce(sum(x."amount") filter (where x."outcome" = 'open' and x."forecast_category" is distinct from 'omit' and x."expected_close_on" >= deal_forecast.since and x."expected_close_on" <= deal_forecast.until and x."forecast_category" = 'best_case'), 0)::text,
      'pipeline', coalesce(sum(x."amount") filter (where x."outcome" = 'open' and x."forecast_category" is distinct from 'omit' and x."expected_close_on" >= deal_forecast.since and x."expected_close_on" <= deal_forecast.until and x."forecast_category" = 'pipeline'), 0)::text,
      'notCalled', coalesce(sum(x."amount") filter (where x."outcome" = 'open' and x."forecast_category" is distinct from 'omit' and x."expected_close_on" >= deal_forecast.since and x."expected_close_on" <= deal_forecast.until and x."forecast_category" is null), 0)::text,
      'omit', coalesce(sum(x."amount") filter (where x."outcome" = 'open' and x."expected_close_on" >= deal_forecast.since and x."expected_close_on" <= deal_forecast.until and x."forecast_category" = 'omit'), 0)::text,
      'later', coalesce(sum(x."amount") filter (where x."outcome" = 'open' and x."forecast_category" is distinct from 'omit' and x."expected_close_on" > deal_forecast.until), 0)::text
    ) as sums
    from scoped x
  ),
  owners as (
    select coalesce(jsonb_agg(o.value order by o.owner_id), '[]'::jsonb) as list
    from (
      select x."owner_id" as owner_id, jsonb_build_object('ownerId', x."owner_id", 
      'won', coalesce(sum(x."amount") filter (where x."outcome" = 'won' and x."closed_at"::date >= deal_forecast.since and x."closed_at"::date <= deal_forecast.until), 0)::text,
      'commit', coalesce(sum(x."amount") filter (where x."outcome" = 'open' and x."forecast_category" is distinct from 'omit' and x."expected_close_on" >= deal_forecast.since and x."expected_close_on" <= deal_forecast.until and x."forecast_category" = 'commit'), 0)::text,
      'bestCase', coalesce(sum(x."amount") filter (where x."outcome" = 'open' and x."forecast_category" is distinct from 'omit' and x."expected_close_on" >= deal_forecast.since and x."expected_close_on" <= deal_forecast.until and x."forecast_category" = 'best_case'), 0)::text,
      'pipeline', coalesce(sum(x."amount") filter (where x."outcome" = 'open' and x."forecast_category" is distinct from 'omit' and x."expected_close_on" >= deal_forecast.since and x."expected_close_on" <= deal_forecast.until and x."forecast_category" = 'pipeline'), 0)::text,
      'notCalled', coalesce(sum(x."amount") filter (where x."outcome" = 'open' and x."forecast_category" is distinct from 'omit' and x."expected_close_on" >= deal_forecast.since and x."expected_close_on" <= deal_forecast.until and x."forecast_category" is null), 0)::text,
      'omit', coalesce(sum(x."amount") filter (where x."outcome" = 'open' and x."expected_close_on" >= deal_forecast.since and x."expected_close_on" <= deal_forecast.until and x."forecast_category" = 'omit'), 0)::text,
      'later', coalesce(sum(x."amount") filter (where x."outcome" = 'open' and x."forecast_category" is distinct from 'omit' and x."expected_close_on" > deal_forecast.until), 0)::text
      ) as value
      from scoped x group by x."owner_id"
    ) o
  )
  select totals.sums || jsonb_build_object(
    'currency', upper(deal_forecast.currency),
    'target', deal_forecast.target::text,
    'attainment', case when coalesce(deal_forecast.target, 0) = 0 then null
      else round(((totals.sums ->> 'won')::numeric + (totals.sums ->> 'commit')::numeric) / deal_forecast.target, 4) end,
    'gap', case when deal_forecast.target is null then null
      else greatest(deal_forecast.target - (totals.sums ->> 'won')::bigint - (totals.sums ->> 'commit')::bigint, 0)::text end,
    'owners', owners.list)
  from totals, owners;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.decide_quote (
  quote    uuid,
  decision text,
  note     text,
  by       text,
  selected jsonb DEFAULT NULL::jsonb,
  actor    jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."quotes";
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = decide_quote.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false)) for update;
  if v_row."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  
  if decide_quote.decision not in ('accepted', 'rejected', 'changes_requested') then
    raise exception 'answer accepted, rejected or changes_requested' using errcode = '22023', hint = 'QUOTE_DECISION_INVALID';
  end if;
  if v_row."status" not in ('sent', 'viewed') then
    raise exception 'this quote no longer takes an answer' using errcode = '55000', hint = 'QUOTE_NOT_OPEN';
  end if;
  if decide_quote.actor is not null then
    if jsonb_typeof(decide_quote.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(decide_quote.actor ->> 'ip', '')::inet, nullif(decide_quote.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(decide_quote.actor::text, ''), true);
  if (decide_quote.actor is not null) and v_row."valid_until" < current_date then
    update "better_supabase"."quotes" x set "status" = 'expired', "updated_at" = now() where x."id" = v_row."id"
    returning * into v_row;
    perform "better_supabase".emit_event('quote.expired', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier"), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
    return (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'unit', ql."unit", 'discountKind', ql."discount_kind", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
  end if;
  if decide_quote.decision = 'accepted' then
    if decide_quote.selected is not null then
      if jsonb_typeof(decide_quote.selected) <> 'array' or exists (
        select 1 from jsonb_array_elements(decide_quote.selected) e
        where jsonb_typeof(e.value) not in ('number') or not exists (
          select 1 from "better_supabase"."quote_lines" ql
          where ql."parent_id" = v_row."id" and ql."optional" and ql."position" = (e.value #>> '{}')::numeric
        )
      ) then
        raise exception 'pick optional lines of this quote by position' using errcode = '22023', hint = 'QUOTE_SELECTION_INVALID';
      end if;
      update "better_supabase"."quote_lines" ql set "selected" = ql."position" in (select ((e.value #>> '{}')::numeric)::integer from jsonb_array_elements(decide_quote.selected) e)
      where ql."parent_id" = v_row."id" and ql."optional";
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_quote_accept"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  perform set_config('better_supabase.transition_reason', coalesce(nullif(trim(decide_quote.note), ''), ''), true);
  update "better_supabase"."quotes" x set "status" = decide_quote.decision, "decided_at" = now(), "decided_by" = nullif(trim(coalesce(nullif(trim(decide_quote.by), ''), nullif(trim(decide_quote.actor ->> 'name'), ''), decide_quote.actor ->> 'email')), ''),
    "decision_note" = nullif(trim(decide_quote.note), ''), "decider_id" = coalesce(nullif(decide_quote.actor ->> 'id', '')::uuid, auth.uid()), "decided_ip" = left(decide_quote.actor ->> 'ip', 64), "decided_user_agent" = left(decide_quote.actor ->> 'userAgent', 512), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform set_config('better_supabase.transition_reason', '', true);
  case decide_quote.decision
    when 'accepted' then
      perform "better_supabase".emit_event('quote.accepted', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'total', v_row."total"::text, 'currency', v_row."currency", 'byName', v_row."decided_by", 'revision', v_row."revision", 'depositDue', v_row."deposit_due"::text), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
    when 'rejected' then
      perform "better_supabase".emit_event('quote.rejected', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'note', v_row."decision_note"), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
    else
      perform "better_supabase".emit_event('quote.changes_requested', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'note', v_row."decision_note"), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
  end case;
  if v_row."owner_id" is not null then
    if better_supabase.import_run() is null then
      v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'quote.decided',
      'tenant', v_row."tenant_id",
      'subject_type', 'quote',
      'subject_id', v_row."id"::text,
      'subject_label', v_row."identifier" || ' ' || v_row."title",
      'summary', v_row."identifier" || ' ' || v_row."title",
      'recipients', jsonb_build_array(v_row."owner_id"),
      'key', 'quote.decided:' || v_row."id"::text,
      'data', jsonb_build_object('quoteId', v_row."id", 'status', v_row."status")
    ));
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
  end if;
  if decide_quote.decision = 'accepted' then
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_quote_accept"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  return (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'unit', ql."unit", 'discountKind', ql."discount_kind", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.decide_shift_swap (
  swap_id     uuid,
  approve     boolean,
  approval_id uuid    DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_shift "better_supabase"."shifts"%rowtype;
  v_row "better_supabase"."shift_assignments"%rowtype;
  v_swap "better_supabase"."shift_swaps"%rowtype;
  v_status text;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_swap from "better_supabase"."shift_swaps" x where x."id" = decide_shift_swap.swap_id for update;
  if not found then
    raise exception 'shift swap not found' using errcode = 'P0002', hint = 'SHIFT_SWAP_NOT_FOUND';
  end if;
  if (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_swap."tenant_id", 'shifts.manage'), false)) then
    v_status := case when coalesce(decide_shift_swap.approve, false) then 'approved' else 'rejected' end;
  elsif v_swap."from_id" = (select auth.uid()) and not coalesce(decide_shift_swap.approve, false) then
    v_status := 'canceled';
  else
    raise exception 'not allowed to decide shift swaps' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if v_swap."status" <> 'pending' then
    raise exception 'the swap is already decided' using errcode = '22023', hint = 'SHIFT_SWAP_INVALID';
  end if;
  if decide_shift_swap.approval_id is not null and not exists (
    select 1 from "better_supabase"."approval_requests" o where o."id" = decide_shift_swap.approval_id and o."tenant_id" = v_swap."tenant_id"
  ) then
    raise exception 'the approval isn''t in this organization' using errcode = '22023', hint = 'SHIFT_SWAP_INVALID';
  end if;
  select * into v_row from "better_supabase"."shift_assignments" x where x."id" = v_swap."assignment_id";
  select * into v_shift from "better_supabase"."shifts" x where x."id" = v_row."shift_id" for update;
  if v_status = 'approved' then
    if v_row."status" <> 'assigned' or v_shift."status" = 'canceled' then
      raise exception 'the shift is no longer assigned to the member who asked' using errcode = '22023', hint = 'SHIFT_SWAP_INVALID';
    end if;
    perform "better_supabase"."shift_assignment_check"(v_shift."id", v_swap."to_id", null);
    update "better_supabase"."shift_assignments" x set "status" = 'released', "updated_at" = now()
    where x."id" = v_row."id"
    returning x.* into v_row;
    perform "better_supabase".emit_event('shift_assignment.released', jsonb_build_object('organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'assignmentId', v_row."id", 'userId', v_row."user_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'reason', 'swapped'), 'shifts/' || v_row."shift_id"::text, (v_row."tenant_id")::text, null, 'better-supabase/shifts');
  perform better_supabase.audit_event(
    event_type => 'shift_assignment.released',
    category => 'data',
    target_type => 'shift_assignment',
    record_id => v_row."id"::text,
    summary => 'Shift assignment released',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'assignmentId', v_row."id", 'userId', v_row."user_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'reason', 'swapped')
  );
    begin
      insert into "better_supabase"."shift_assignments" ("tenant_id", "shift_id", "user_id", "status", "starts_at", "ends_at", "assigned_by")
  values (v_shift."tenant_id", v_shift."id", v_swap."to_id", 'assigned', v_shift."starts_at", v_shift."ends_at", (select auth.uid()))
  on conflict ("shift_id", "user_id") do update set "status" = 'assigned', "starts_at" = excluded."starts_at", "ends_at" = excluded."ends_at", "assigned_by" = excluded."assigned_by", "updated_at" = now()
  returning * into v_row;
    exception when exclusion_violation then
      raise exception 'the member has another shift at that time' using errcode = '23P01', hint = 'SHIFT_ASSIGNMENT_OVERLAP';
    end;
    perform "better_supabase".emit_event('shift_assignment.created', jsonb_build_object('organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'assignmentId', v_row."id", 'userId', v_row."user_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at"), 'shifts/' || v_row."shift_id"::text, (v_row."tenant_id")::text, null, 'better-supabase/shifts');
  perform better_supabase.audit_event(
    event_type => 'shift_assignment.created',
    category => 'data',
    target_type => 'shift_assignment',
    record_id => v_row."id"::text,
    summary => 'Shift assignment created',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'assignmentId', v_row."id", 'userId', v_row."user_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at")
  );
  end if;
  update "better_supabase"."shift_swaps" x set "status" = v_status, "decided_at" = now(), "decided_by" = (select auth.uid()), "approval_id" = coalesce(decide_shift_swap.approval_id, x."approval_id")
  where x."id" = v_swap."id"
  returning x.* into v_swap;
  perform "better_supabase".emit_event('shift_swap.decided', jsonb_build_object('organizationId', v_swap."tenant_id", 'swapId', v_swap."id", 'assignmentId', v_swap."assignment_id", 'shiftId', v_shift."id", 'fromUserId', v_swap."from_id", 'toUserId', v_swap."to_id", 'status', v_swap."status"), 'shifts/' || v_shift."id"::text, (v_swap."tenant_id")::text, null, 'better-supabase/shifts');
  perform better_supabase.audit_event(
    event_type => 'shift_swap.decided',
    category => 'data',
    target_type => 'shift_swap',
    record_id => v_swap."id"::text,
    summary => 'Shift swap decided',
    tenant => (v_swap."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_swap."tenant_id", 'swapId', v_swap."id", 'assignmentId', v_swap."assignment_id", 'shiftId', v_shift."id", 'fromUserId', v_swap."from_id", 'toUserId', v_swap."to_id", 'status', v_swap."status")
  );
  if v_status <> 'canceled' then
    if better_supabase.import_run() is null then
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'shift_swap.decided',
      'tenant', v_shift."tenant_id",
      'actor', (select auth.uid()),
      'subject_type', 'shift',
      'subject_id', v_shift."id"::text,
      'summary', 'Your shift swap is decided',
      'recipients', jsonb_build_array(v_swap."from_id"),
      'key', 'shift_swap.decided:' || v_shift."id"::text || ':' || v_swap."from_id"::text,
      'data', jsonb_build_object('startsAt', v_shift."starts_at", 'endsAt', v_shift."ends_at")
    ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  end if;
  if v_status = 'approved' then
    if better_supabase.import_run() is null then
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'shift_assignment.created',
      'tenant', v_shift."tenant_id",
      'actor', (select auth.uid()),
      'subject_type', 'shift',
      'subject_id', v_shift."id"::text,
      'summary', 'You took over a shift',
      'recipients', jsonb_build_array(v_swap."to_id"),
      'key', 'shift_assignment.created:' || v_shift."id"::text || ':' || v_swap."to_id"::text,
      'data', jsonb_build_object('startsAt', v_shift."starts_at", 'endsAt', v_shift."ends_at")
    ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  end if;
  return jsonb_build_object('id', v_swap."id", 'organizationId', v_swap."tenant_id", 'assignmentId', v_swap."assignment_id", 'fromUserId', v_swap."from_id", 'toUserId', v_swap."to_id", 'status', v_swap."status", 'approvalId', v_swap."approval_id", 'note', v_swap."note", 'decidedBy', v_swap."decided_by", 'decidedAt', v_swap."decided_at", 'createdAt', v_swap."created_at");
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
  v_subjects jsonb := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = delete_activity.engagement), '[]'::jsonb);
  v_first jsonb := v_subjects -> 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if exists (select 1 from "better_supabase"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the engagement is locked: add an addendum with amend_activity instead' using errcode = '55000', hint = 'ACTIVITY_LOCKED';
  end if;
  delete from "better_supabase"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false))
  returning x."tenant_id", x."type" into v_tenant, v_type;
  if v_tenant is null then
    return false;
  end if;
  perform "better_supabase".emit_event('activity.deleted', jsonb_build_object('organizationId', v_tenant, 'engagementId', v_id, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects), 'engagements/' || v_id::text, (v_tenant::text)::text, null, 'better-supabase/activities');
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_deal (
  deal uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."deals";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from "better_supabase"."deals" x
  where x."id" = delete_deal.deal
    and ((auth.role() = 'service_role') or x."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.manage'), false))
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  perform "better_supabase".emit_event('deal.deleted', jsonb_build_object('organizationId', v_row."tenant_id", 'dealId', v_row."id", 'subjectType', 'deal', 'subjectId', v_row."id"::text, 'name', v_row."name"), 'deals/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/deals');
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.enrollment_json (
  enrollment_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'id', x."id", 'organizationId', x."tenant_id", 'program', x."program", 'programVersion', x."program_version",
    'subjectType', x."subject_type", 'subjectId', x."subject_id", 'status', x."status",
    'steps', to_jsonb(x."steps"), 'completedSteps', x."completed_steps", 'totalSteps', cardinality(x."steps"),
    'enrolledBy', x."enrolled_by", 'enrolledAt', x."enrolled_at", 'completedAt', x."completed_at",
    'cancelledAt', x."cancelled_at", 'pausedAt', x."paused_at", 'cancelReason', x."cancel_reason",
    'updatedAt', x."updated_at",
    'progress', coalesce((
      select jsonb_agg(jsonb_build_object('step', y."step", 'completedAt', y."completed_at", 'completedBy', y."completed_by") order by y."completed_at", array_position(x."steps", y."step"), y."step")
      from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id" and y."completed_at" is not null
    ), '[]'::jsonb),
    'startsAt', x."starts_at", 'endsAt', x."ends_at",
    'schedule', coalesce((
      select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('step', y."step", 'assignee', case when y."assignee_role" is not null then jsonb_build_object('role', y."assignee_role") when y."assignee_id" is not null then jsonb_build_object('userId', y."assignee_id") end, 'dueAt', y."due_at", 'completedAt', y."completed_at")) order by array_position(x."steps", y."step"), y."step")
      from "better_supabase"."enrollment_steps" y
      where y."enrollment_id" = x."id"
        and (y."assignee_role" is not null or y."assignee_id" is not null or y."due_at" is not null)
    ), '[]'::jsonb)
  )
  from "better_supabase"."enrollments" x
  where x."id" = enrollment_json.enrollment_id
$function$;

CREATE OR REPLACE FUNCTION better_supabase.enrollment_schedule (
  target uuid
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."enrollments";
  v_program "better_supabase"."enrollment_programs";
  v_plan jsonb;
begin
  select * into v_row from "better_supabase"."enrollments" x where x."id" = enrollment_schedule.target;
  if v_row."id" is null or v_row."tenant_id" is null or position(':' in v_row."program") > 0 then
    return;
  end if;
  select * into v_program from "better_supabase"."enrollment_programs" x
  where x."tenant_id" = v_row."tenant_id" and x."key" = v_row."program";
  v_plan := coalesce((
    select jsonb_agg(jsonb_build_object(
      'step', t.value ->> 'id',
      'role', t.value -> 'assignee' ->> 'role',
      'userId', t.value -> 'assignee' ->> 'userId',
      'dueAt', case t.value -> 'due' ->> 'from'
        when 'start' then coalesce(v_row."starts_at", v_row."enrolled_at") + make_interval(days => (t.value -> 'due' ->> 'days')::integer)
        when 'end' then v_row."ends_at" + make_interval(days => (t.value -> 'due' ->> 'days')::integer)
      end
    ))
    from jsonb_array_elements(coalesce(v_program."steps", '[]'::jsonb)) as t(value)
    where t.value ->> 'id' = any(v_row."steps")
      and (jsonb_typeof(t.value -> 'assignee') = 'object' or jsonb_typeof(t.value -> 'due') = 'object')
  ), '[]'::jsonb);
  delete from "better_supabase"."enrollment_steps" y
  where y."enrollment_id" = v_row."id" and y."completed_at" is null and not exists (select 1 from jsonb_array_elements(v_plan) as z(value) where z.value ->> 'step' = y."step");
  update "better_supabase"."enrollment_steps" y
  set "assignee_role" = null, "assignee_id" = null, "due_at" = null
  where y."enrollment_id" = v_row."id" and not exists (select 1 from jsonb_array_elements(v_plan) as z(value) where z.value ->> 'step' = y."step")
    and (y."assignee_role" is not null or y."assignee_id" is not null or y."due_at" is not null);
  insert into "better_supabase"."enrollment_steps" as y ("enrollment_id", "tenant_id", "step", "assignee_role", "assignee_id", "due_at", "completed_by", "completed_at")
  select v_row."id", v_row."tenant_id", z.value ->> 'step', z.value ->> 'role', (z.value ->> 'userId')::uuid, (z.value ->> 'dueAt')::timestamptz, null, null
  from jsonb_array_elements(v_plan) as z(value)
  on conflict ("enrollment_id", "step") do update
  set "assignee_role" = excluded."assignee_role", "assignee_id" = excluded."assignee_id", "due_at" = excluded."due_at";
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.enrollment_step (
  enrollment_id uuid,
  step          text,
  done          boolean
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."enrollments";
begin
  select * into v_row from "better_supabase"."enrollments" x where x."id" = enrollment_step.enrollment_id;
  if v_row."id" is null or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'enrollments.read'), false))) or (v_row."user_id" is not null and coalesce(v_row."user_id" = auth.uid(), false)) or exists (select 1 from "better_supabase"."enrollment_steps" a where a."enrollment_id" = v_row."id" and a."step" = enrollment_step.step and a."assignee_id" = auth.uid())) then
    raise exception 'enrollment not found' using errcode = 'P0002', hint = 'ENROLLMENTS_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'enrollments.enroll'), false))) or (v_row."user_id" is not null and coalesce(v_row."user_id" = auth.uid(), false)) or exists (select 1 from "better_supabase"."enrollment_steps" a where a."enrollment_id" = v_row."id" and a."step" = enrollment_step.step and a."assignee_id" = auth.uid())) then
    raise exception 'not allowed to change this enrollment' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  -- A course's steps follow its lessons, so they change only through courses.
  if v_row."program" like 'course:%' then
    raise exception 'this enrollment belongs to a course; complete its lessons through courses' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  -- A sequence's steps run on its schedule, so only its runner marks them.
  if v_row."program" like 'sequence:%' then
    raise exception 'this enrollment belongs to a sequence; its steps run on the sequence''s schedule' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  perform "better_supabase"."enrollment_mark"(v_row."id", enrollment_step.step, enrollment_step.done, auth.uid());
  return "better_supabase"."enrollment_json"(v_row."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.forecast_changes (
  from_snapshot uuid,
  to_snapshot   uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_from "better_supabase"."forecast_snapshots";
  v_to "better_supabase"."forecast_snapshots";
begin
  select * into v_from from "better_supabase"."forecast_snapshots" x where x."id" = forecast_changes.from_snapshot;
  select * into v_to from "better_supabase"."forecast_snapshots" x where x."id" = forecast_changes.to_snapshot;
  if v_from."id" is null or v_to."id" is null
    or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_from."tenant_id", 'forecasts.read'), false)) or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_to."tenant_id", 'forecasts.read'), false)) then
    raise exception 'No forecast snapshot you can read has this id' using errcode = 'P0002', hint = 'FORECAST_NOT_FOUND';
  end if;
  if v_from."tenant_id" <> v_to."tenant_id" or v_from."currency" <> v_to."currency" then
    raise exception 'Both snapshots must be of one organization and currency' using errcode = '22023', hint = 'FORECAST_MISMATCH';
  end if;
  return jsonb_build_object(
    'from', jsonb_build_object('id', v_from."id", 'organizationId', v_from."tenant_id", 'pipelineId', v_from."pipeline_id", 'since', v_from."period_start", 'until', v_from."period_end", 'currency', v_from."currency", 'target', v_from."target"::text, 'totals', v_from."totals", 'dealCount', v_from."deal_count", 'takenBy', v_from."taken_by", 'takenAt', v_from."taken_at"),
    'to', jsonb_build_object('id', v_to."id", 'organizationId', v_to."tenant_id", 'pipelineId', v_to."pipeline_id", 'since', v_to."period_start", 'until', v_to."period_end", 'currency', v_to."currency", 'target', v_to."target"::text, 'totals', v_to."totals", 'dealCount', v_to."deal_count", 'takenBy', v_to."taken_by", 'takenAt', v_to."taken_at"),
    'deals', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'dealId', coalesce(b."deal_id", a."deal_id"),
        'name', coalesce(b."name", a."name"),
        'change', case
      when a."deal_id" is null then 'added'
      when b."deal_id" is null then 'removed'
      when a."outcome" = 'open' and b."outcome" = 'won' then 'won'
      when a."outcome" = 'open' and b."outcome" = 'lost' then 'lost'
      else 'changed'
    end,
        'before', case when a."deal_id" is null then null else jsonb_build_object('dealId', a."deal_id", 'name', a."name", 'ownerId', a."owner_id", 'stageId', a."stage_id", 'forecast', a."forecast_category"::text, 'outcome', a."outcome"::text, 'amount', a."amount"::text, 'closeOn', a."expected_close_on", 'closedAt', a."closed_at") end,
        'after', case when b."deal_id" is null then null else jsonb_build_object('dealId', b."deal_id", 'name', b."name", 'ownerId', b."owner_id", 'stageId', b."stage_id", 'forecast', b."forecast_category"::text, 'outcome', b."outcome"::text, 'amount', b."amount"::text, 'closeOn', b."expected_close_on", 'closedAt', b."closed_at") end
      ) order by coalesce(b."amount", a."amount") desc, coalesce(b."deal_id", a."deal_id")), '[]'::jsonb)
      from (select * from "better_supabase"."forecast_snapshot_deals" where "snapshot_id" = v_from."id") a
      full join (select * from "better_supabase"."forecast_snapshot_deals" where "snapshot_id" = v_to."id") b on b."deal_id" = a."deal_id"
      where a."deal_id" is null or b."deal_id" is null
      or a."amount" <> b."amount"
      or a."outcome" <> b."outcome"
      or a."forecast_category" is distinct from b."forecast_category"
      or a."stage_id" is distinct from b."stage_id"
      or a."expected_close_on" is distinct from b."expected_close_on"
      or a."owner_id" is distinct from b."owner_id"
    ));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.forecast_snapshot (
  snapshot uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."forecast_snapshots";
begin
  select * into v_row from "better_supabase"."forecast_snapshots" x where x."id" = forecast_snapshot.snapshot;
  if v_row."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'forecasts.read'), false)) then
    raise exception 'No forecast snapshot you can read has this id' using errcode = 'P0002', hint = 'FORECAST_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'pipelineId', v_row."pipeline_id", 'since', v_row."period_start", 'until', v_row."period_end", 'currency', v_row."currency", 'target', v_row."target"::text, 'totals', v_row."totals", 'dealCount', v_row."deal_count", 'takenBy', v_row."taken_by", 'takenAt', v_row."taken_at") || jsonb_build_object('deals', (
    select coalesce(jsonb_agg(jsonb_build_object('dealId', y."deal_id", 'name', y."name", 'ownerId', y."owner_id", 'stageId', y."stage_id", 'forecast', y."forecast_category"::text, 'outcome', y."outcome"::text, 'amount', y."amount"::text, 'closeOn', y."expected_close_on", 'closedAt', y."closed_at") order by y."amount" desc, y."deal_id"), '[]'::jsonb)
    from "better_supabase"."forecast_snapshot_deals" y where y."snapshot_id" = v_row."id"
  ));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_appraisal (
  appraisal_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."appraisals";
begin
  select * into v_row from "better_supabase"."appraisals" x where x."id" = get_appraisal.appraisal_id;
  if not found or not coalesce((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'appraisals.read'), false))) or (v_row."appraisee_id" = auth.uid()
    or exists (select 1 from "better_supabase"."appraisal_reviews" z where z."appraisal_id" = v_row."id" and z."reviewer_id" = auth.uid())), false) then
    raise exception 'no such appraisal' using errcode = 'P0002', hint = 'APPRAISALS_NOT_FOUND';
  end if;
  return "better_supabase"."appraisal_json"(v_row."id", (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'appraisals.read'), false))));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_booking_series (
  series_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object('id', sr."id", 'organizationId', sr."tenant_id"::text, 'serviceId', sr."service_id", 'resourceId', sr."resource_id", 'rule', sr."rule", 'startsAt', sr."starts_at", 'tz', sr."tz", 'customerName', sr."customer_name", 'customerEmail', sr."customer_email", 'customerUserId', sr."customer_id", 'status', sr."status", 'endsAt', sr."ends_at", 'createdAt', sr."created_at") || jsonb_build_object('bookings', coalesce((
    select jsonb_agg(jsonb_build_object('id', bk."id", 'resourceId', bk."resource_id", 'serviceId', bk."service_id", 'seat', bk."seat", 'startsAt', lower(bk."during"), 'endsAt', upper(bk."during"), 'status', bk."status", 'holdExpiresAt', bk."hold_expires_at", 'customerName', bk."customer_name", 'customerEmail', bk."customer_email", 'customerUserId', bk."customer_id", 'notes', bk."notes", 'seriesId', bk."series_id", 'createdAt', bk."created_at", 'cancelledAt', bk."cancelled_at", 'cancelReason', bk."cancel_reason") order by lower(bk."during"))
    from "better_supabase"."bookings" bk where bk."series_id" = sr."id"
  ), '[]'::jsonb))
  from "better_supabase"."booking_series" sr
  where sr."id" = get_booking_series.series_id
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_pass (
  pass_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."passes"%rowtype;
begin
  select * into v_row from "better_supabase"."passes" x where x."id" = get_pass.pass_id;
  if not found or not (coalesce(v_row."holder_id" = auth.uid(), false) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'passes.manage'), false))) then
    return null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id"::text, 'kind', v_row."kind", 'holderUserId', v_row."holder_id", 'holderName', v_row."holder_name", 'holderEmail', v_row."holder_email", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'bookingId', v_row."booking_id", 'resourceId', v_row."resource_id", 'usesAllowed', v_row."uses_allowed", 'uses', v_row."uses", 'validFrom', v_row."starts_at", 'validUntil', v_row."expires_at", 'status', v_row."status", 'issuedBy', v_row."issued_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'revokedAt', v_row."revoked_at") || jsonb_build_object('nonce', v_row."nonce");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.goal_progress (
  tenant  uuid,
  on_date date,
  owner   uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg((to_jsonb(p) || jsonb_build_object('goal', p."goal"::text, 'actual', p."actual"::text)) - 'period_start_order' - 'name_order' order by p.period_start_order, p.name_order), '[]'::jsonb)
  from (
    select x.*, v.value::text as progress, round(v.value::numeric / x."goal", 4) as attainment, x."period_start" as period_start_order, x."name" as name_order
    from "better_supabase"."goals" x
    cross join lateral (select case x."metric"
        when 'deals.won_amount' then (select coalesce(sum(d."amount"), 0) from "better_supabase"."deals" d where d."tenant_id" = x."tenant_id" and d."outcome" = 'won' and d."closed_at"::date between x."period_start" and x."period_end"
        and (x."owner_id" is null or d."owner_id" = x."owner_id") and d."currency" = x."currency")
        when 'deals.won_count' then (select count(*) from "better_supabase"."deals" d where d."tenant_id" = x."tenant_id" and d."outcome" = 'won' and d."closed_at"::date between x."period_start" and x."period_end"
        and (x."owner_id" is null or d."owner_id" = x."owner_id"))
        when 'work_items.completed' then (select count(*) from "better_supabase"."work_items" w
      where w."tenant_id" = x."tenant_id" and w."state" = 'completed' and w."closed_at"::date between x."period_start" and x."period_end"
        and (x."team_id" is null or w."team_id" = x."team_id")
        and (x."owner_id" is null or exists (select 1 from "better_supabase"."work_item_assignees" a where a."work_item_id" = w."id" and a."user_id" = x."owner_id")))
        when 'invoices.paid_amount' then (select coalesce(sum(e."amount"), 0) from "better_supabase"."ledger_entries" e
      join "better_supabase"."ledger_accounts" a on a."id" = e."account_id"
      join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
      where a."tenant_id" = x."tenant_id" and a."managed_by" = 'invoices' and a."code" = 'invoices:cash:' || x."currency" and y."effective_at"::date between x."period_start" and x."period_end")
        else x."actual"
      end as value) v
    where x."tenant_id" = goal_progress.tenant and x."archived_at" is null
      and coalesce(goal_progress.on_date, current_date) between x."period_start" and x."period_end"
      and (goal_progress.owner is null or x."owner_id" = goal_progress.owner)
  ) p
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
  starts_at    timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  expires_at   timestamp with time zone DEFAULT NULL::timestamp WITH time zone
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
  v_until timestamptz := issue_pass.expires_at;
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
      when 'activity' then (select s."tenant_id"::text from "better_supabase"."activities" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'quote' then (select s."tenant_id"::text from "better_supabase"."quotes" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'work_item' then (select s."tenant_id"::text from "better_supabase"."work_items" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'employee' then (select s."tenant_id"::text from "better_supabase"."employees" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'invoice' then (select s."tenant_id"::text from "better_supabase"."invoices" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'ledger_account' then (select s."tenant_id"::text from "better_supabase"."ledger_accounts" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'product' then (select s."tenant_id"::text from "better_supabase"."products" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'product_variant' then (select s."tenant_id"::text from "better_supabase"."product_variants" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'rfq' then (select s."tenant_id"::text from "better_supabase"."rfqs" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'till' then (select s."tenant_id"::text from "better_supabase"."tills" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'order' then (select s."tenant_id"::text from "better_supabase"."orders" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'calendar_event' then (select s."tenant_id"::text from "better_supabase"."calendar_events" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'booking' then (select s."tenant_id"::text from "better_supabase"."bookings" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'asset' then (select s."tenant_id"::text from "better_supabase"."assets" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'asset_location' then (select s."tenant_id"::text from "better_supabase"."asset_locations" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'lease' then (select s."tenant_id"::text from "better_supabase"."leases" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'expense_report' then (select s."tenant_id"::text from "better_supabase"."expense_reports" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'expense_line' then (select s."tenant_id"::text from "better_supabase"."expense_lines" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'donation_fund' then (select s."tenant_id"::text from "better_supabase"."donation_funds" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'work_order' then (select s."tenant_id"::text from "better_supabase"."work_orders" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'shipment' then (select s."tenant_id"::text from "better_supabase"."shipments" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'contract' then (select s."tenant_id"::text from "better_supabase"."contracts" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'control' then (select s."tenant_id"::text from "better_supabase"."controls" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'compliance_policy' then (select s."tenant_id"::text from "better_supabase"."compliance_policies" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'qualification_type' then (select s."tenant_id"::text from "better_supabase"."qualification_types" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'risk' then (select s."tenant_id"::text from "better_supabase"."risks" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'case' then (select s."tenant_id"::text from "better_supabase"."cases" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'inspection' then (select s."tenant_id"::text from "better_supabase"."inspections" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'inspection_program' then (select s."tenant_id"::text from "better_supabase"."inspection_programs" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'inspection_finding' then (select s."tenant_id"::text from "better_supabase"."inspection_findings" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'form' then (select s."tenant_id"::text from "better_supabase"."forms" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'meeting' then (select s."tenant_id"::text from "better_supabase"."meetings" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'meeting_decision' then (select s."tenant_id"::text from "better_supabase"."meeting_decisions" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'maintenance_plan' then (select s."tenant_id"::text from "better_supabase"."maintenance_plans" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'dam_usage_right' then (select s."tenant_id"::text from "better_supabase"."dam_usage_rights" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'lims_sample' then (select s."tenant_id"::text from "better_supabase"."lims_samples" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'tax_code' then (select s."tenant_id"::text from "better_supabase"."tax_codes" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'production_order' then (select s."tenant_id"::text from "better_supabase"."production_orders" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'work_center' then (select s."tenant_id"::text from "better_supabase"."work_centers" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'bank_account' then (select s."tenant_id"::text from "better_supabase"."bank_accounts" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'care_plan' then (select s."tenant_id"::text from "better_supabase"."care_plans" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'incident' then (select s."tenant_id"::text from "better_supabase"."incidents" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'content_entry' then (select s."tenant_id"::text from "better_supabase"."content_entries" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'document' then (select s."tenant_id"::text from "better_supabase"."documents" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'customer' then (select s."organization_id"::text from "public"."customers" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'drive_node' then (select s."tenant_id"::text from "better_supabase"."drive_nodes" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'application' then (select s."tenant_id"::text from "better_supabase"."applications" s where s."id" = (issue_pass.subject_id)::uuid)
      when 'change_request' then (select s."organization_id"::text from "public"."change_requests" s where s."id" = (issue_pass.subject_id)::uuid)
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
  if v_until is not null and v_until <= coalesce(issue_pass.starts_at, now()) then
    raise exception 'expires_at must be after starts_at and in the future' using errcode = '22023', hint = 'PASS_VALIDITY_INVALID';
  end if;
  insert into "better_supabase"."passes" ("tenant_id", "kind", "holder_id", "holder_name", "holder_email", "subject_type", "subject_id", "booking_id", "resource_id", "uses_allowed", "starts_at", "expires_at", "nonce", "issued_by")
  values (issue_pass.tenant, coalesce(issue_pass.kind, 'ticket'), issue_pass.holder_user, issue_pass.holder_name, lower(btrim(issue_pass.holder_email)),
    issue_pass.subject_type, issue_pass.subject_id, issue_pass.booking_id, v_resource,
    case when issue_pass.booking_id is not null then coalesce(issue_pass.uses_allowed, 1) else issue_pass.uses_allowed end,
    coalesce(issue_pass.starts_at, now()), v_until, encode(extensions.gen_random_bytes(16), 'hex'), auth.uid())
  returning * into v_row;
  perform "better_supabase".emit_event('pass.issued', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'kind', v_row."kind", 'holderUserId', v_row."holder_id", 'bookingId', v_row."booking_id"), 'passes/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/passes');
  perform better_supabase.audit_event(
    event_type => 'pass.issued',
    category => 'access',
    target_type => 'pass',
    record_id => v_row."id"::text,
    summary => 'issued pass ' || v_row."kind",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'kind', v_row."kind", 'holderUserId', v_row."holder_id", 'bookingId', v_row."booking_id")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id"::text, 'kind', v_row."kind", 'holderUserId', v_row."holder_id", 'holderName', v_row."holder_name", 'holderEmail', v_row."holder_email", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'bookingId', v_row."booking_id", 'resourceId', v_row."resource_id", 'usesAllowed', v_row."uses_allowed", 'uses', v_row."uses", 'validFrom', v_row."starts_at", 'validUntil', v_row."expires_at", 'status', v_row."status", 'issuedBy', v_row."issued_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'revokedAt', v_row."revoked_at") || jsonb_build_object('nonce', v_row."nonce");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_activity (
  tenant       uuid,
  subject_type text                     DEFAULT NULL::text,
  subject_id   text                     DEFAULT NULL::text,
  before       timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  max_rows     integer                  DEFAULT 50,
  sources      text[]                   DEFAULT NULL::text[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_limit integer := least(greatest(coalesce(list_activity.max_rows, 50), 1), 500);
  v_rows jsonb;
  v_table text;
begin
  if list_activity.subject_id is not null and list_activity.subject_type = any ('{message,conversation,channel,company,person,deal,course,post,activity,quote,work_item,employee,invoice,ledger_account,product,product_variant,rfq,till,order,calendar_event,booking,asset,asset_location,lease,expense_report,expense_line,donation_fund,work_order,shipment,contract,control,compliance_policy,qualification_type,risk,case,inspection,inspection_program,inspection_finding,form,meeting,meeting_decision,maintenance_plan,dam_usage_right,lims_sample,tax_code,production_order,work_center,bank_account,care_plan,incident,content_entry,document,customer,drive_node,application,change_request,project,task}'::text[])
    and not "better_supabase"."activity_subject_readable"(list_activity.subject_type, list_activity.subject_id) then
    return '[]'::jsonb;
  end if;
  if list_activity.subject_id is not null then
    v_table := case list_activity.subject_type
      when 'message' then 'better_supabase.messages'
      when 'conversation' then 'better_supabase.conversations'
      when 'channel' then 'better_supabase.channels'
      when 'company' then 'better_supabase.companies'
      when 'person' then 'better_supabase.people'
      when 'deal' then 'better_supabase.deals'
      when 'course' then 'better_supabase.courses'
      when 'post' then 'better_supabase.posts'
      when 'activity' then 'better_supabase.activities'
      when 'quote' then 'better_supabase.quotes'
      when 'work_item' then 'better_supabase.work_items'
      when 'employee' then 'better_supabase.employees'
      when 'invoice' then 'better_supabase.invoices'
      when 'ledger_account' then 'better_supabase.ledger_accounts'
      when 'product' then 'better_supabase.products'
      when 'product_variant' then 'better_supabase.product_variants'
      when 'rfq' then 'better_supabase.rfqs'
      when 'till' then 'better_supabase.tills'
      when 'order' then 'better_supabase.orders'
      when 'calendar_event' then 'better_supabase.calendar_events'
      when 'booking' then 'better_supabase.bookings'
      when 'asset' then 'better_supabase.assets'
      when 'asset_location' then 'better_supabase.asset_locations'
      when 'lease' then 'better_supabase.leases'
      when 'expense_report' then 'better_supabase.expense_reports'
      when 'expense_line' then 'better_supabase.expense_lines'
      when 'donation_fund' then 'better_supabase.donation_funds'
      when 'work_order' then 'better_supabase.work_orders'
      when 'shipment' then 'better_supabase.shipments'
      when 'contract' then 'better_supabase.contracts'
      when 'control' then 'better_supabase.controls'
      when 'compliance_policy' then 'better_supabase.compliance_policies'
      when 'qualification_type' then 'better_supabase.qualification_types'
      when 'risk' then 'better_supabase.risks'
      when 'case' then 'better_supabase.cases'
      when 'inspection' then 'better_supabase.inspections'
      when 'inspection_program' then 'better_supabase.inspection_programs'
      when 'inspection_finding' then 'better_supabase.inspection_findings'
      when 'form' then 'better_supabase.forms'
      when 'meeting' then 'better_supabase.meetings'
      when 'meeting_decision' then 'better_supabase.meeting_decisions'
      when 'maintenance_plan' then 'better_supabase.maintenance_plans'
      when 'dam_usage_right' then 'better_supabase.dam_usage_rights'
      when 'lims_sample' then 'better_supabase.lims_samples'
      when 'tax_code' then 'better_supabase.tax_codes'
      when 'production_order' then 'better_supabase.production_orders'
      when 'work_center' then 'better_supabase.work_centers'
      when 'bank_account' then 'better_supabase.bank_accounts'
      when 'care_plan' then 'better_supabase.care_plans'
      when 'incident' then 'better_supabase.incidents'
      when 'content_entry' then 'better_supabase.content_entries'
      when 'document' then 'better_supabase.documents'
      when 'customer' then 'public.customers'
      when 'drive_node' then 'better_supabase.drive_nodes'
      when 'application' then 'better_supabase.applications'
      when 'change_request' then 'public.change_requests'
      when 'project' then 'public.projects'
      when 'task' then 'public.tasks'
    end;
  end if;
  select coalesce(jsonb_agg(x.entry order by x.at desc, x.id desc), '[]'::jsonb)
  into v_rows
  from (
    select u.entry, u.at, u.id from (
    (select to_jsonb(y.*) || jsonb_build_object('source', 'event') as entry,
      y."occurred_at" as at, y."id"::text as id
    from "better_supabase"."timeline_entries" y
    where y."organization_id" = list_activity.tenant
      and (list_activity.sources is null or 'event' = any (list_activity.sources))
      and (list_activity.subject_type is null or y."subject_type" = list_activity.subject_type)
      and (list_activity.subject_id is null or y."subject_id" = list_activity.subject_id)
      and (list_activity.before is null or y."occurred_at" < list_activity.before)
      and not ((y."type" = 'status.changed' and list_activity.subject_id is not null
      and list_activity.subject_type = any ('{message,conversation,channel,company,person,deal,course,post,activity,quote,work_item,employee,invoice,ledger_account,product,product_variant,rfq,till,order,calendar_event,booking,asset,asset_location,lease,expense_report,expense_line,donation_fund,work_order,shipment,contract,control,compliance_policy,qualification_type,risk,case,inspection,inspection_program,inspection_finding,form,meeting,meeting_decision,maintenance_plan,dam_usage_right,lims_sample,tax_code,production_order,work_center,bank_account,care_plan,incident,content_entry,document,customer,drive_node,application,change_request,project,task}'::text[])
      and list_activity.subject_type = any ('{work_item,change_request,drive_node}'::text[])
      and (list_activity.sources is null or 'transition' = any (list_activity.sources)))
        or (y."type" in ('message.sent', 'comment.posted') and list_activity.subject_id is not null
      and list_activity.subject_type = any ('{message,conversation,channel,company,person,deal,course,post,activity,quote,work_item,employee,invoice,ledger_account,product,product_variant,rfq,till,order,calendar_event,booking,asset,asset_location,lease,expense_report,expense_line,donation_fund,work_order,shipment,contract,control,compliance_policy,qualification_type,risk,case,inspection,inspection_program,inspection_finding,form,meeting,meeting_decision,maintenance_plan,dam_usage_right,lims_sample,tax_code,production_order,work_center,bank_account,care_plan,incident,content_entry,document,customer,drive_node,application,change_request,project,task}'::text[])
      and (list_activity.sources is null or 'message' = any (list_activity.sources))))
    order by y."occurred_at" desc, y."id" desc
    limit v_limit)
    union all
    (select jsonb_build_object('id', l."id"::text, 'organization_id', l."organization_id", 'event_id', null::text, 'type', coalesce(l."event_type", 'audit.' || l."op"), 'actor_id', l."actor_id", 'subject_type', list_activity.subject_type, 'subject_id', list_activity.subject_id, 'summary', l."summary", 'data', jsonb_strip_nulls(jsonb_build_object('op', l."op", 'changed', to_jsonb(l."changed"), 'table', l."table_name")), 'occurred_at', l."occurred_at", 'source', 'audit') as entry,
      l."occurred_at" as at, l."id"::text as id
    from "better_supabase"."audit_events" l
    where v_table is not null
      and (list_activity.sources is null or 'audit' = any (list_activity.sources))
      and l."table_name" = v_table
      and l."record_id" = list_activity.subject_id
      and l."organization_id" = list_activity.tenant
      and (list_activity.before is null or l."occurred_at" < list_activity.before)
    order by l."occurred_at" desc, l."id" desc
    limit v_limit)
    union all
    (select jsonb_build_object('id', r."id"::text, 'organization_id', r."tenant_id", 'event_id', null::text, 'type', 'run.' || r."status", 'actor_id', r."actor_id", 'subject_type', list_activity.subject_type, 'subject_id', list_activity.subject_id, 'summary', null::text, 'data', jsonb_strip_nulls(jsonb_build_object('runId', r."id", 'definition', r."definition", 'engine', r."engine", 'status', r."status", 'mode', r."mode", 'error', r."error"::text, 'completedAt', r."completed_at")), 'occurred_at', r."created_at", 'source', 'run') as entry,
      r."created_at" as at, r."id"::text as id
    from "better_supabase"."workflow_runs" r
    where list_activity.subject_id is not null
      and list_activity.subject_type = any ('{message,conversation,channel,company,person,deal,course,post,activity,quote,work_item,employee,invoice,ledger_account,product,product_variant,rfq,till,order,calendar_event,booking,asset,asset_location,lease,expense_report,expense_line,donation_fund,work_order,shipment,contract,control,compliance_policy,qualification_type,risk,case,inspection,inspection_program,inspection_finding,form,meeting,meeting_decision,maintenance_plan,dam_usage_right,lims_sample,tax_code,production_order,work_center,bank_account,care_plan,incident,content_entry,document,customer,drive_node,application,change_request,project,task}'::text[])
      and (list_activity.sources is null or 'run' = any (list_activity.sources))
      and r."tenant_id" = list_activity.tenant
      and r."subject_type" = list_activity.subject_type
      and r."subject_id" = list_activity.subject_id
      and (list_activity.before is null or r."created_at" < list_activity.before)
    order by r."created_at" desc, r."id" desc
    limit v_limit)
    union all
    (select jsonb_build_object('id', h."id"::text, 'organization_id', h."tenant_id", 'event_id', null::text, 'type', 'status.changed', 'actor_id', h."actor_id", 'subject_type', list_activity.subject_type, 'subject_id', list_activity.subject_id, 'summary', null::text, 'data', jsonb_strip_nulls(jsonb_build_object('from', h."from_status"::text, 'to', h."to_status"::text, 'reason', h."reason")), 'occurred_at', h."created_at", 'source', 'transition') as entry,
      h."created_at" as at, h."id"::text as id
    from "better_supabase"."status_history" h
    where list_activity.subject_id is not null
      and list_activity.subject_type = any ('{message,conversation,channel,company,person,deal,course,post,activity,quote,work_item,employee,invoice,ledger_account,product,product_variant,rfq,till,order,calendar_event,booking,asset,asset_location,lease,expense_report,expense_line,donation_fund,work_order,shipment,contract,control,compliance_policy,qualification_type,risk,case,inspection,inspection_program,inspection_finding,form,meeting,meeting_decision,maintenance_plan,dam_usage_right,lims_sample,tax_code,production_order,work_center,bank_account,care_plan,incident,content_entry,document,customer,drive_node,application,change_request,project,task}'::text[])
      and list_activity.subject_type = any ('{work_item,change_request,drive_node}'::text[])
      and (list_activity.sources is null or 'transition' = any (list_activity.sources))
      and h."tenant_id" = list_activity.tenant
      and h."subject_type" = list_activity.subject_type
      and h."subject_id" = list_activity.subject_id
      and (list_activity.before is null or h."created_at" < list_activity.before)
    order by h."created_at" desc, h."id" desc
    limit v_limit)
    union all
    (select jsonb_build_object('id', m."id"::text, 'organization_id', m."tenant_id", 'event_id', null::text, 'type', case when c."kind" = 'subject' then 'comment.posted' else 'message.sent' end, 'actor_id', m."author_id", 'subject_type', list_activity.subject_type, 'subject_id', list_activity.subject_id, 'summary', left(m."body", 280), 'data', jsonb_strip_nulls(jsonb_build_object('messageId', m."id", 'conversationId', m."conversation_id", 'threadId', m."thread_id", 'kind', m."kind"::text)), 'occurred_at', m."sent_at", 'source', 'message') as entry,
      m."sent_at" as at, m."id"::text as id
    from "better_supabase"."messages" m
    join "better_supabase"."conversations" c on c."id" = m."conversation_id"
    where list_activity.subject_id is not null
      and list_activity.subject_type = any ('{message,conversation,channel,company,person,deal,course,post,activity,quote,work_item,employee,invoice,ledger_account,product,product_variant,rfq,till,order,calendar_event,booking,asset,asset_location,lease,expense_report,expense_line,donation_fund,work_order,shipment,contract,control,compliance_policy,qualification_type,risk,case,inspection,inspection_program,inspection_finding,form,meeting,meeting_decision,maintenance_plan,dam_usage_right,lims_sample,tax_code,production_order,work_center,bank_account,care_plan,incident,content_entry,document,customer,drive_node,application,change_request,project,task}'::text[])
      and (list_activity.sources is null or 'message' = any (list_activity.sources))
      and c."tenant_id" = list_activity.tenant
      and c."subject_type" = list_activity.subject_type
      and c."subject_id" = list_activity.subject_id
      and m."sent_at" is not null
      and m."archived_at" is null
      and (list_activity.before is null or m."sent_at" < list_activity.before)
    order by m."sent_at" desc, m."id" desc
    limit v_limit)
    union all
    (select d.entry, d.at, d.id
    from "better_supabase"."activity_subject_deliveries"(list_activity.tenant, list_activity.subject_type, list_activity.subject_id, list_activity.before, v_limit) d
    where list_activity.subject_id is not null
      and (list_activity.sources is null or 'delivery' = any (list_activity.sources)))
    ) u
    order by u.at desc, u.id desc
    limit v_limit
  ) x;
  if list_activity.subject_id is not null and jsonb_array_length(v_rows) > 0 then
    perform "better_supabase"."record_subject_read"(list_activity.subject_type, list_activity.subject_id, null, 'timeline', 'list_activity');
  end if;
  return v_rows;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_ai_chat_participants (
  chat uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not "better_supabase"."ai_chat_can_read"(list_ai_chat_participants.chat) then
    raise exception 'No chat %', list_ai_chat_participants.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  return (
    select jsonb_build_array(jsonb_build_object('id', null, 'chat_id', c."id", 'user_id', c."owner_id", 'kind', 'user', 'team_id', null, 'customer_id', null, 'email', null, 'role', 'owner', 'added_by', null, 'created_at', c."created_at"))
      || coalesce((
        select jsonb_agg(jsonb_build_object('id', x."id", 'chat_id', x."chat_id", 'user_id', x."user_id", 'kind', x."kind", 'team_id', x."team_id", 'customer_id', x."customer_id", 'email', x."email", 'role', x."role", 'added_by', x."added_by", 'created_at', x."created_at") order by x."created_at", x."id")
        from "better_supabase"."ai_chat_participants" x
        where x."chat_id" = list_ai_chat_participants.chat
      ), '[]'::jsonb)
    from "better_supabase"."ai_chats" c where c."id" = list_ai_chat_participants.chat
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_ai_chats (
  tenant   uuid    DEFAULT NULL::uuid,
  search   text    DEFAULT NULL::text,
  project  uuid    DEFAULT NULL::uuid,
  pinned   boolean DEFAULT NULL::boolean,
  archived boolean DEFAULT false,
  after    text    DEFAULT NULL::text,
  size     integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_uid uuid := auth.uid();
  v_query tsquery;
  v_at timestamptz;
  v_id uuid;
  v_size integer := least(greatest(coalesce(list_ai_chats.size, 50), 1), 200);
  v_items jsonb;
  v_next text;
begin
  if v_uid is null then
    return jsonb_build_object('items', '[]'::jsonb, 'next', null);
  end if;
  if nullif(btrim(list_ai_chats.search), '') is not null then
    v_query := websearch_to_tsquery('simple'::regconfig, list_ai_chats.search);
  end if;
  if list_ai_chats.after is not null then
    v_at := split_part(list_ai_chats.after, '|', 1)::timestamptz;
    v_id := split_part(list_ai_chats.after, '|', 2)::uuid;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', page."id", 'organization_id', page."organization_id", 'owner_id', page."owner_id", 'project_id', page."project_id", 'agent_id', page."agent_id", 'title', page."title", 'model', page."model", 'visibility', page."visibility", 'mode', page."mode", 'pinned', page."pinned", 'archived_at', page."archived_at", 'is_temporary', page."is_temporary", 'expires_at', page."expires_at", 'current_leaf_id', page."current_leaf_id", 'active_stream_id', page."active_stream_id", 'active_run_id', page."active_run_id", 'last_message_at', page."last_message_at", 'created_at', page."created_at", 'updated_at', page."updated_at") order by page."last_message_at" desc, page."id" desc), '[]'::jsonb)
  into v_items
  from (
    select x.* from "better_supabase"."ai_chats" x
    where (x."owner_id" = v_uid or (x."visibility" <> 'private' and exists (select 1 from "better_supabase"."ai_chat_participants" pa where pa."chat_id" = x."id" and ((((pa."kind"::text = 'user' and pa."user_id" = (select auth.uid())) or (pa."kind"::text = 'team' and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = pa."team_id"::text and tm."user_id" = (select auth.uid())))) and (x."organization_id" is null or x."organization_id" in (select better_supabase.member_organization_ids()))) or (pa."kind"::text = 'customer' and pa."customer_id" = (select auth.uid()) and ((x."organization_id")::text, ('ai-chat')::text, (x."id"::text)::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g))))))
      and not x."is_temporary"
      and (list_ai_chats.tenant is null or x."organization_id" = list_ai_chats.tenant)
      and (list_ai_chats.project is null or x."project_id" = list_ai_chats.project)
      and (list_ai_chats.pinned is null or x."pinned" = list_ai_chats.pinned)
      and (list_ai_chats.archived is null or (x."archived_at" is not null) = list_ai_chats.archived)
      and (v_at is null or (x."last_message_at", x."id") < (v_at, v_id))
      and (
        v_query is null
        or x."search_tsv" @@ v_query
        or exists (select 1 from "better_supabase"."ai_messages" mm where mm."chat_id" = x."id" and mm."search_tsv" @@ v_query)
      )
    order by x."last_message_at" desc, x."id" desc
    limit v_size + 1
  ) page;
  if jsonb_array_length(v_items) > v_size then
    v_items := v_items - v_size;
    v_next := (v_items -> (v_size - 1) ->> 'last_message_at') || '|' || (v_items -> (v_size - 1) ->> 'id');
  end if;
  return jsonb_build_object('items', v_items, 'next', v_next);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_appraisals (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_appraisals.filters, '{}'::jsonb);
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_all boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_appraisals.tenant is not null and coalesce(better_supabase.can('tenant', list_appraisals.tenant, 'appraisals.read'), false)));
begin
  return coalesce((
    select jsonb_agg("better_supabase"."appraisal_json"(y.id, v_all) order by y.created_at desc, y.id)
    from (
      select x."id" as id, x."created_at" as created_at
      from "better_supabase"."appraisals" x
      where x."tenant_id" = list_appraisals.tenant
        and (not v_filters ? 'cycleId' or x."cycle_id" = (v_filters ->> 'cycleId')::uuid)
        and (not v_filters ? 'status' or x."status" = v_filters ->> 'status')
        and (not v_filters ? 'subjectUserId' or x."appraisee_id" = (v_filters ->> 'subjectUserId')::uuid)
        and ((v_all and (v_filters ->> 'mine') is distinct from 'true') or (x."appraisee_id" = auth.uid()
    or exists (select 1 from "better_supabase"."appraisal_reviews" z where z."appraisal_id" = x."id" and z."reviewer_id" = auth.uid())))
      order by x."created_at" desc, x."id"
      limit v_limit offset coalesce((v_filters ->> 'offset')::integer, 0)
    ) y
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_booking_resources (
  tenant           uuid,
  include_inactive boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', rs."id", 'name', rs."name", 'kind', rs."kind",
    'capacity', rs."capacity", 'tz', rs."tz", 'active', rs."active",
    'calendarId', rs."calendar_id",
    'hostUserId', rs."host_id"
  ) order by rs."name", rs."id"), '[]'::jsonb)
  from "better_supabase"."booking_resources" rs
  where rs."tenant_id" = list_booking_resources.tenant
    and (list_booking_resources.include_inactive or rs."active")
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_bookings (
  tenant      uuid,
  range_start timestamp with time zone,
  range_end   timestamp with time zone,
  resource    uuid                     DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', bk."id", 'resourceId', bk."resource_id", 'serviceId', bk."service_id", 'seat', bk."seat", 'startsAt', lower(bk."during"), 'endsAt', upper(bk."during"), 'status', bk."status", 'holdExpiresAt', bk."hold_expires_at", 'customerName', bk."customer_name", 'customerEmail', bk."customer_email", 'customerUserId', bk."customer_id", 'notes', bk."notes", 'seriesId', bk."series_id", 'createdAt', bk."created_at", 'cancelledAt', bk."cancelled_at", 'cancelReason', bk."cancel_reason") order by lower(bk."during"), bk."id"), '[]'::jsonb)
  from "better_supabase"."bookings" bk
  where bk."tenant_id" = list_bookings.tenant
    and bk."during" && tstzrange(list_bookings.range_start, list_bookings.range_end)
    and (list_bookings.resource is null or bk."resource_id" = list_bookings.resource)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_companies (
  tenant          uuid,
  search          text,
  lifecycle       text,
  owner           uuid,
  after_name      text,
  after_id        uuid,
  page_size       integer,
  role            text    DEFAULT NULL::text,
  supplier_status text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_like text := '%' || replace(replace(replace(coalesce(list_companies.search, ''), '\', '\\'), '%', '\%'), '_', '\_') || '%';
begin
  return coalesce((
    select jsonb_agg(to_jsonb(p) || jsonb_build_object('roles', p."roles", 'customer_terms_id', p."customer_terms_id", 'supplier_terms_id', p."supplier_terms_id", 'credit_currency', p."credit_currency", 'credit_limit', p."credit_limit"::text, 'credit_block', p."credit_block", 'supplier_status', p."supplier_status", 'language', p."language") order by lower(p."name"), p."id")
    from (
      select x.* from "better_supabase"."companies" x
      where x."tenant_id" = list_companies.tenant
        and x."archived_at" is null
        and (list_companies.search is null or x."name" ilike v_like or x."domain" ilike v_like)
        and (list_companies.lifecycle is null or x."lifecycle" = list_companies.lifecycle)
        and (list_companies.owner is null or x."owner_id" = list_companies.owner)
        and (list_companies.role is null or list_companies.role = any (x."roles"))
        and (list_companies.supplier_status is null or x."supplier_status" = list_companies.supplier_status)
        and (list_companies.after_name is null or (lower(x."name"), x."id") > (lower(list_companies.after_name), list_companies.after_id))
      order by lower(x."name"), x."id"
      limit least(greatest(coalesce(list_companies.page_size, 50), 1), 200)
    ) p
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_consents (
  subject_type    text,
  subject_id      text,
  include_history boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_tenant uuid := ((case list_consents.subject_type
      when 'message' then (select s."tenant_id"::text from "better_supabase"."messages" s where s."id" = (list_consents.subject_id)::uuid)
      when 'conversation' then (select s."tenant_id"::text from "better_supabase"."conversations" s where s."id" = (list_consents.subject_id)::uuid)
      when 'channel' then (select s."tenant_id"::text from "better_supabase"."channels" s where s."id" = (list_consents.subject_id)::uuid)
      when 'company' then (select s."tenant_id"::text from "better_supabase"."companies" s where s."id" = (list_consents.subject_id)::uuid)
      when 'person' then (select s."tenant_id"::text from "better_supabase"."people" s where s."id" = (list_consents.subject_id)::uuid)
      when 'deal' then (select s."tenant_id"::text from "better_supabase"."deals" s where s."id" = (list_consents.subject_id)::uuid)
      when 'course' then (select s."tenant_id"::text from "better_supabase"."courses" s where s."id" = (list_consents.subject_id)::uuid)
      when 'post' then (select s."tenant_id"::text from "better_supabase"."posts" s where s."id" = (list_consents.subject_id)::uuid)
      when 'activity' then (select s."tenant_id"::text from "better_supabase"."activities" s where s."id" = (list_consents.subject_id)::uuid)
      when 'quote' then (select s."tenant_id"::text from "better_supabase"."quotes" s where s."id" = (list_consents.subject_id)::uuid)
      when 'work_item' then (select s."tenant_id"::text from "better_supabase"."work_items" s where s."id" = (list_consents.subject_id)::uuid)
      when 'employee' then (select s."tenant_id"::text from "better_supabase"."employees" s where s."id" = (list_consents.subject_id)::uuid)
      when 'invoice' then (select s."tenant_id"::text from "better_supabase"."invoices" s where s."id" = (list_consents.subject_id)::uuid)
      when 'ledger_account' then (select s."tenant_id"::text from "better_supabase"."ledger_accounts" s where s."id" = (list_consents.subject_id)::uuid)
      when 'product' then (select s."tenant_id"::text from "better_supabase"."products" s where s."id" = (list_consents.subject_id)::uuid)
      when 'product_variant' then (select s."tenant_id"::text from "better_supabase"."product_variants" s where s."id" = (list_consents.subject_id)::uuid)
      when 'rfq' then (select s."tenant_id"::text from "better_supabase"."rfqs" s where s."id" = (list_consents.subject_id)::uuid)
      when 'till' then (select s."tenant_id"::text from "better_supabase"."tills" s where s."id" = (list_consents.subject_id)::uuid)
      when 'order' then (select s."tenant_id"::text from "better_supabase"."orders" s where s."id" = (list_consents.subject_id)::uuid)
      when 'calendar_event' then (select s."tenant_id"::text from "better_supabase"."calendar_events" s where s."id" = (list_consents.subject_id)::uuid)
      when 'booking' then (select s."tenant_id"::text from "better_supabase"."bookings" s where s."id" = (list_consents.subject_id)::uuid)
      when 'asset' then (select s."tenant_id"::text from "better_supabase"."assets" s where s."id" = (list_consents.subject_id)::uuid)
      when 'asset_location' then (select s."tenant_id"::text from "better_supabase"."asset_locations" s where s."id" = (list_consents.subject_id)::uuid)
      when 'lease' then (select s."tenant_id"::text from "better_supabase"."leases" s where s."id" = (list_consents.subject_id)::uuid)
      when 'expense_report' then (select s."tenant_id"::text from "better_supabase"."expense_reports" s where s."id" = (list_consents.subject_id)::uuid)
      when 'expense_line' then (select s."tenant_id"::text from "better_supabase"."expense_lines" s where s."id" = (list_consents.subject_id)::uuid)
      when 'donation_fund' then (select s."tenant_id"::text from "better_supabase"."donation_funds" s where s."id" = (list_consents.subject_id)::uuid)
      when 'work_order' then (select s."tenant_id"::text from "better_supabase"."work_orders" s where s."id" = (list_consents.subject_id)::uuid)
      when 'shipment' then (select s."tenant_id"::text from "better_supabase"."shipments" s where s."id" = (list_consents.subject_id)::uuid)
      when 'contract' then (select s."tenant_id"::text from "better_supabase"."contracts" s where s."id" = (list_consents.subject_id)::uuid)
      when 'control' then (select s."tenant_id"::text from "better_supabase"."controls" s where s."id" = (list_consents.subject_id)::uuid)
      when 'compliance_policy' then (select s."tenant_id"::text from "better_supabase"."compliance_policies" s where s."id" = (list_consents.subject_id)::uuid)
      when 'qualification_type' then (select s."tenant_id"::text from "better_supabase"."qualification_types" s where s."id" = (list_consents.subject_id)::uuid)
      when 'risk' then (select s."tenant_id"::text from "better_supabase"."risks" s where s."id" = (list_consents.subject_id)::uuid)
      when 'case' then (select s."tenant_id"::text from "better_supabase"."cases" s where s."id" = (list_consents.subject_id)::uuid)
      when 'inspection' then (select s."tenant_id"::text from "better_supabase"."inspections" s where s."id" = (list_consents.subject_id)::uuid)
      when 'inspection_program' then (select s."tenant_id"::text from "better_supabase"."inspection_programs" s where s."id" = (list_consents.subject_id)::uuid)
      when 'inspection_finding' then (select s."tenant_id"::text from "better_supabase"."inspection_findings" s where s."id" = (list_consents.subject_id)::uuid)
      when 'form' then (select s."tenant_id"::text from "better_supabase"."forms" s where s."id" = (list_consents.subject_id)::uuid)
      when 'meeting' then (select s."tenant_id"::text from "better_supabase"."meetings" s where s."id" = (list_consents.subject_id)::uuid)
      when 'meeting_decision' then (select s."tenant_id"::text from "better_supabase"."meeting_decisions" s where s."id" = (list_consents.subject_id)::uuid)
      when 'maintenance_plan' then (select s."tenant_id"::text from "better_supabase"."maintenance_plans" s where s."id" = (list_consents.subject_id)::uuid)
      when 'dam_usage_right' then (select s."tenant_id"::text from "better_supabase"."dam_usage_rights" s where s."id" = (list_consents.subject_id)::uuid)
      when 'lims_sample' then (select s."tenant_id"::text from "better_supabase"."lims_samples" s where s."id" = (list_consents.subject_id)::uuid)
      when 'tax_code' then (select s."tenant_id"::text from "better_supabase"."tax_codes" s where s."id" = (list_consents.subject_id)::uuid)
      when 'production_order' then (select s."tenant_id"::text from "better_supabase"."production_orders" s where s."id" = (list_consents.subject_id)::uuid)
      when 'work_center' then (select s."tenant_id"::text from "better_supabase"."work_centers" s where s."id" = (list_consents.subject_id)::uuid)
      when 'bank_account' then (select s."tenant_id"::text from "better_supabase"."bank_accounts" s where s."id" = (list_consents.subject_id)::uuid)
      when 'care_plan' then (select s."tenant_id"::text from "better_supabase"."care_plans" s where s."id" = (list_consents.subject_id)::uuid)
      when 'incident' then (select s."tenant_id"::text from "better_supabase"."incidents" s where s."id" = (list_consents.subject_id)::uuid)
      when 'content_entry' then (select s."tenant_id"::text from "better_supabase"."content_entries" s where s."id" = (list_consents.subject_id)::uuid)
      when 'document' then (select s."tenant_id"::text from "better_supabase"."documents" s where s."id" = (list_consents.subject_id)::uuid)
      when 'customer' then (select s."organization_id"::text from "public"."customers" s where s."id" = (list_consents.subject_id)::uuid)
      when 'drive_node' then (select s."tenant_id"::text from "better_supabase"."drive_nodes" s where s."id" = (list_consents.subject_id)::uuid)
      when 'application' then (select s."tenant_id"::text from "better_supabase"."applications" s where s."id" = (list_consents.subject_id)::uuid)
      when 'change_request' then (select s."organization_id"::text from "public"."change_requests" s where s."id" = (list_consents.subject_id)::uuid)
      when 'project' then (select s."organization_id"::text from "public"."projects" s where s."id" = (list_consents.subject_id)::uuid)
      when 'task' then (select s."organization_id"::text from "public"."tasks" s where s."id" = (list_consents.subject_id)::uuid)
      else null::text
    end))::uuid;
begin
  if v_tenant is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
      or (coalesce(better_supabase.can('tenant', v_tenant, 'consents.read'), false) and coalesce("better_supabase"."can_subject"(list_consents.subject_type, list_consents.subject_id, 'read'), false))
      or ((v_tenant)::text, (list_consents.subject_type)::text, (list_consents.subject_id)::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g)
      or ((v_tenant)::text, (list_consents.subject_type)::text, (list_consents.subject_id)::text) in (select g.tenant, g.party_type, g.party_id from better_supabase.portal_parties() g)
      or exists (select 1 from "better_supabase"."relations" r
      where r."kind" = 'represents' and r."source_type" = 'person'
        and r."tenant_id"::text = (v_tenant)::text
        and r."target_type" = list_consents.subject_type and r."target_id" = (list_consents.subject_id)::text
        and r."data" ->> 'authority' in ('inform', 'act')
        and (case when r."data" ->> 'valid_from' is null then true
      when pg_input_is_valid(r."data" ->> 'valid_from', 'date') then (r."data" ->> 'valid_from')::date <= current_date
      else false end) and (case when r."data" ->> 'valid_until' is null then true
      when pg_input_is_valid(r."data" ->> 'valid_until', 'date') then (r."data" ->> 'valid_until')::date >= current_date
      else false end)
        and ((v_tenant)::text, ('person')::text, (r."source_id")::text) in (select g.tenant, g.party_type, g.party_id from better_supabase.portal_parties() g))) then
    raise exception 'not allowed to read the consents of this record' using errcode = '42501', hint = 'CONSENT_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(l.item order by l.key, l.created desc, l.id), '[]'::jsonb)
    from (
      select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'purposeId', x."purpose_id", 'purposeKey', y."key", 'purposeTitle', y."title", 'purposeVersion', y."version", 'legalBasis', y."legal_basis", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'givenBy', x."given_by", 'givenByContactId', x."given_by_contact_id", 'givenByUserId', x."grantor_id", 'status', x."status", 'scope', coalesce(x."scope", '{}'::jsonb), 'grantedAt', x."granted_at", 'validUntil', x."expires_at", 'withdrawnAt', x."withdrawn_at", 'withdrawnReason', x."withdrawn_reason", 'signatureId', x."signature_id", 'submissionId', x."submission_id", 'attachmentId', x."attachment_id", 'createdBy', x."created_by", 'createdAt', x."created_at", 'active', (x."status" = 'granted' and (x."expires_at" is null or x."expires_at" > now()))) as item, y."key" as key, x."created_at" as created, x."id" as id,
        row_number() over (partition by y."key" order by x."created_at" desc, x."id" desc) as n
      from "better_supabase"."consents" x
      join "better_supabase"."consent_purposes" y on y."id" = x."purpose_id"
      where x."tenant_id" = v_tenant
        and x."subject_type" = list_consents.subject_type and x."subject_id" = list_consents.subject_id
    ) l
    where coalesce(list_consents.include_history, false) or l.n = 1
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_pass_check_ins (
  pass_id   uuid,
  before    timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  page_size integer                  DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_pass "better_supabase"."passes"%rowtype;
begin
  select * into v_pass from "better_supabase"."passes" x where x."id" = list_pass_check_ins.pass_id;
  if not found or not (coalesce(v_pass."holder_id" = auth.uid(), false) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_pass."tenant_id", 'passes.read'), false))) then
    return '[]'::jsonb;
  end if;
  return (
    select coalesce(jsonb_agg(z.item order by z.created desc, z.id desc), '[]'::jsonb)
    from (
      select jsonb_build_object('id', y."id", 'organizationId', y."tenant_id"::text, 'passId', y."pass_id", 'resourceId', y."resource_id", 'bookingId', y."booking_id", 'gate', y."gate", 'method', y."method", 'admitted', y."admitted", 'reason', y."reason", 'checkedInBy', y."checked_in_by", 'createdAt', y."created_at") as item, y."created_at" as created, y."id" as id
      from "better_supabase"."pass_check_ins" y
      where y."pass_id" = v_pass."id"
        and (list_pass_check_ins.before is null or y."created_at" < list_pass_check_ins.before)
      order by y."created_at" desc, y."id" desc
      limit least(greatest(coalesce(list_pass_check_ins.page_size, 50), 1), 500)
    ) z
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_pass_credits (
  pass_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_pass "better_supabase"."passes"%rowtype;
begin
  select * into v_pass from "better_supabase"."passes" x where x."id" = list_pass_credits.pass_id;
  if not found or not (coalesce(v_pass."holder_id" = auth.uid(), false) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_pass."tenant_id", 'passes.read'), false))) then
    raise exception 'pass not found' using errcode = 'P0002', hint = 'PASS_NOT_FOUND';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', r."id", 'organizationId', r."tenant_id"::text, 'passId', (x."metadata" ->> 'passId')::uuid,
      'bookingId', r."reference_id"::uuid, 'delta', y."amount",
      'reason', case when r."kind" = 'pass.credit_used' then 'booking' else 'refund' end,
      'createdBy', r."actor_id", 'createdAt', r."created_at") order by r."effective_at" desc, r."created_at" desc, r."id")
    from "better_supabase"."ledger_accounts" x
    join "better_supabase"."ledger_entries" y on y."account_id" = x."id"
    join "better_supabase"."ledger_transactions" r on r."id" = y."transaction_id"
    where x."tenant_id" = v_pass."tenant_id" and x."code" = 'pass:' || v_pass."id"::text
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_passes (
  tenant       uuid,
  holder_user  uuid                     DEFAULT NULL::uuid,
  subject_type text                     DEFAULT NULL::text,
  subject_id   text                     DEFAULT NULL::text,
  status       text                     DEFAULT NULL::text,
  before       timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  page_size    integer                  DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_passes.tenant, 'passes.read'), false)) then
    raise exception 'not allowed to read passes' using errcode = '42501', hint = 'PASS_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(z.item order by z.created desc, z.id desc), '[]'::jsonb)
    from (
      select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'kind', x."kind", 'holderUserId', x."holder_id", 'holderName', x."holder_name", 'holderEmail', x."holder_email", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'bookingId', x."booking_id", 'resourceId', x."resource_id", 'usesAllowed', x."uses_allowed", 'uses', x."uses", 'validFrom', x."starts_at", 'validUntil', x."expires_at", 'status', x."status", 'issuedBy', x."issued_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'revokedAt', x."revoked_at") as item, x."created_at" as created, x."id" as id
      from "better_supabase"."passes" x
      where x."tenant_id" = list_passes.tenant
        and (list_passes.holder_user is null or x."holder_id" = list_passes.holder_user)
        and (list_passes.subject_type is null or (x."subject_type" = list_passes.subject_type and x."subject_id" = list_passes.subject_id))
        and (list_passes.status is null or x."status" = list_passes.status)
        and (list_passes.before is null or x."created_at" < list_passes.before)
      order by x."created_at" desc, x."id" desc
      limit least(greatest(coalesce(list_passes.page_size, 50), 1), 500)
    ) z
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_people (
  tenant          uuid,
  search          text,
  lifecycle       text,
  owner           uuid,
  after_name      text,
  after_id        uuid,
  page_size       integer,
  role            text    DEFAULT NULL::text,
  supplier_status text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_like text := '%' || replace(replace(replace(coalesce(list_people.search, ''), '\', '\\'), '%', '\%'), '_', '\_') || '%';
begin
  return coalesce((
    select jsonb_agg(to_jsonb(p) || jsonb_build_object('roles', p."roles", 'customer_terms_id', p."customer_terms_id", 'supplier_terms_id', p."supplier_terms_id", 'credit_currency', p."credit_currency", 'credit_limit', p."credit_limit"::text, 'credit_block', p."credit_block", 'supplier_status', p."supplier_status", 'language', p."language") order by lower(p."name"), p."id")
    from (
      select x.* from "better_supabase"."people" x
      where x."tenant_id" = list_people.tenant
        and x."archived_at" is null
        and (list_people.search is null or x."name" ilike v_like or x."email" ilike v_like)
        and (list_people.lifecycle is null or x."lifecycle" = list_people.lifecycle)
        and (list_people.owner is null or x."owner_id" = list_people.owner)
        and (list_people.role is null or list_people.role = any (x."roles"))
        and (list_people.supplier_status is null or x."supplier_status" = list_people.supplier_status)
        and (list_people.after_name is null or (lower(x."name"), x."id") > (lower(list_people.after_name), list_people.after_id))
      order by lower(x."name"), x."id"
      limit least(greatest(coalesce(list_people.page_size, 50), 1), 200)
    ) p
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_referrals (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_referrals.filters, '{}'::jsonb);
  v_all boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_referrals.tenant is not null and coalesce(better_supabase.can('tenant', list_referrals.tenant, 'referrals.read'), false)));
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'codeId', y."code_id", 'referrerId', y."referrer_id", 'referredUserId', y."referred_id", 'referredOrganizationId', y."referred_organization_id", 'referredEmail', y."referred_email", 'status', y."status", 'rewardAmount', y."reward_amount"::text, 'rewardUnit', y."reward_unit", 'qualifiedAt', y."qualified_at", 'rewardedAt', y."rewarded_at", 'ledgerTransactionId', y."ledger_transaction_id", 'createdAt', y."created_at") order by y."created_at" desc)
    from (
      select * from "better_supabase"."referrals" z
      where z."tenant_id" = list_referrals.tenant
        and (v_all or z."referrer_id" = (select auth.uid()))
        and (not v_filters ? 'referrer' or z."referrer_id" = (v_filters ->> 'referrer')::uuid)
        and (not v_filters ? 'status' or z."status" = v_filters ->> 'status')
      order by z."created_at" desc
      limit least(greatest(coalesce((v_filters ->> 'limit')::integer, 100), 1), 500)
    ) y
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_status_history (
  subject_type text,
  subject_id   text,
  before       timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  max_rows     integer                  DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  case list_status_history.subject_type
    when 'work_item' then
      if not exists (select 1 from "better_supabase"."work_items" s where s."id" = (list_status_history.subject_id)::uuid) then
        raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
      end if;
      perform "better_supabase"."record_subject_read"(list_status_history.subject_type, list_status_history.subject_id, null, 'state-machine', 'list_status_history');
      return coalesce((
        select jsonb_agg(jsonb_build_object('id', r.id, 'from', r.from_status, 'to', r.to_status,
          'actorId', r.actor, 'actorName', r."actorName", 'actorEmail', r."actorEmail", 'ip', r.ip, 'userAgent', r."userAgent",
          'reason', r.reason, 'createdAt', r.created_at) order by r.created_at desc, r.id desc)
        from (select h."id"::text as id, h."from_status" as from_status, h."to_status" as to_status,
          h."actor_id"::text as actor, h."actor_name"::text as "actorName", h."actor_email"::text as "actorEmail", regexp_replace(h."ip_address"::text, '/(32|128)$', '') as "ip", h."user_agent"::text as "userAgent", h."reason" as reason, h."created_at" as created_at
        from "better_supabase"."status_history" h
        where h."subject_type" = 'work_item'
          and h."subject_id" = list_status_history.subject_id
          and (list_status_history.before is null or h."created_at" < list_status_history.before)
        order by h."created_at" desc, h."id" desc
        limit least(greatest(coalesce(list_status_history.max_rows, 50), 1), 500)) r
      ), '[]'::jsonb);
    when 'change_request' then
      if not exists (select 1 from "public"."change_requests" s where s."id" = (list_status_history.subject_id)::uuid) then
        raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
      end if;
      perform "better_supabase"."record_subject_read"(list_status_history.subject_type, list_status_history.subject_id, null, 'state-machine', 'list_status_history');
      return coalesce((
        select jsonb_agg(jsonb_build_object('id', r.id, 'from', r.from_status, 'to', r.to_status,
          'actorId', r.actor, 'actorName', r."actorName", 'actorEmail', r."actorEmail", 'ip', r.ip, 'userAgent', r."userAgent",
          'reason', r.reason, 'createdAt', r.created_at) order by r.created_at desc, r.id desc)
        from (select h."id"::text as id, h."from_status" as from_status, h."to_status" as to_status,
          h."actor_id"::text as actor, h."actor_name"::text as "actorName", h."actor_email"::text as "actorEmail", regexp_replace(h."ip_address"::text, '/(32|128)$', '') as "ip", h."user_agent"::text as "userAgent", h."reason" as reason, h."created_at" as created_at
        from "better_supabase"."status_history" h
        where h."subject_type" = 'change_request'
          and h."subject_id" = list_status_history.subject_id
          and (list_status_history.before is null or h."created_at" < list_status_history.before)
        order by h."created_at" desc, h."id" desc
        limit least(greatest(coalesce(list_status_history.max_rows, 50), 1), 500)) r
      ), '[]'::jsonb);
    when 'drive_node' then
      if not exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (list_status_history.subject_id)::uuid) then
        raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
      end if;
      perform "better_supabase"."record_subject_read"(list_status_history.subject_type, list_status_history.subject_id, null, 'state-machine', 'list_status_history');
      return coalesce((
        select jsonb_agg(jsonb_build_object('id', r.id, 'from', r.from_status, 'to', r.to_status,
          'actorId', r.actor, 'actorName', r."actorName", 'actorEmail', r."actorEmail", 'ip', r.ip, 'userAgent', r."userAgent",
          'reason', r.reason, 'createdAt', r.created_at) order by r.created_at desc, r.id desc)
        from (select h."id"::text as id, h."from_status" as from_status, h."to_status" as to_status,
          h."actor_id"::text as actor, h."actor_name"::text as "actorName", h."actor_email"::text as "actorEmail", regexp_replace(h."ip_address"::text, '/(32|128)$', '') as "ip", h."user_agent"::text as "userAgent", h."reason" as reason, h."created_at" as created_at
        from "better_supabase"."status_history" h
        where h."subject_type" = 'drive_node'
          and h."subject_id" = list_status_history.subject_id
          and (list_status_history.before is null or h."created_at" < list_status_history.before)
        order by h."created_at" desc, h."id" desc
        limit least(greatest(coalesce(list_status_history.max_rows, 50), 1), 500)) r
      ), '[]'::jsonb);
    else
      raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
  end case;
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
  if exists (select 1 from "better_supabase"."activities" x where x."tenant_id" = v_tenant and x."external_ref" = log_activity.attrs ->> 'externalRef' and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
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
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
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
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
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
  delete from "better_supabase"."engagement_subjects" x where x."activity_id" = v_id;
  insert into "better_supabase"."engagement_subjects" ("tenant_id", "activity_id", "subject_type", "subject_id", "position")
  select v_tenant, v_id, s.value ->> 'type', s.value ->> 'id', s.ordinality::integer
  from jsonb_array_elements(coalesce(log_activity.subjects, '[]')) with ordinality s
  on conflict do nothing;
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  perform "better_supabase".emit_event('activity.logged', jsonb_build_object('organizationId', v_tenant, 'engagementId', v_id, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects), 'engagements/' || v_id::text, (v_tenant::text)::text, null, 'better-supabase/activities');
  if v_owner is not null and v_owner is distinct from auth.uid() and v_owner is distinct from v_previous_owner then
    if better_supabase.import_run() is null then
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
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_activity_log"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."activities" x where x."id" = v_id);
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
  v_subjects jsonb := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = mark_activity_error.engagement), '[]'::jsonb);
  v_first jsonb := v_subjects -> 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_reason is null then
    raise exception 'say why the engagement is in error' using errcode = '23502', hint = 'ACTIVITY_REASON_REQUIRED';
  end if;
  if exists (select 1 from "better_supabase"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and x."marked_error_at" is not null) then
    raise exception 'the engagement is already marked in error' using errcode = '55000', hint = 'ACTIVITY_ALREADY_MARKED_ERROR';
  end if;
  update "better_supabase"."activities" x set
    "marked_error_at" = now(),
    "marked_error_by" = auth.uid(),
    "marked_error_reason" = v_reason,
    "locked_at" = least(coalesce(x."locked_at", now()), now())
  where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false))
  returning x."tenant_id", x."type"::text into v_tenant, v_type;
  if v_tenant is null then
    raise exception 'no such engagement you can edit' using errcode = 'P0002', hint = 'ACTIVITY_NOT_FOUND';
  end if;
  perform "better_supabase".emit_event('activity.error_marked', jsonb_build_object('organizationId', v_tenant, 'engagementId', v_id, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects, 'reason', v_reason), 'engagements/' || v_id::text, (v_tenant::text)::text, null, 'better-supabase/activities');
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."activities" x where x."id" = v_id);
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
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_keep."tenant_id", 'contacts.manage'), false)) then
    raise exception 'not allowed to change companies and people' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  update "better_supabase"."companies" x set "domain" = null, "merged_into" = merge_companies.keep,
    "archived_at" = coalesce(x."archived_at", now()), "updated_at" = now()
  where x."id" = merge_companies.drop;
  update "better_supabase"."companies" x set "domain" = coalesce(x."domain", v_drop."domain"), "website" = coalesce(x."website", v_drop."website"), "vat_id" = coalesce(x."vat_id", v_drop."vat_id"), "legal_name" = coalesce(x."legal_name", v_drop."legal_name"), "registration_id" = coalesce(x."registration_id", v_drop."registration_id"), "phone" = coalesce(x."phone", v_drop."phone"), "owner_id" = coalesce(x."owner_id", v_drop."owner_id"), "customer_terms_id" = coalesce(x."customer_terms_id", v_drop."customer_terms_id"), "supplier_terms_id" = coalesce(x."supplier_terms_id", v_drop."supplier_terms_id"), "credit_limit" = coalesce(x."credit_limit", v_drop."credit_limit"), "credit_currency" = coalesce(x."credit_currency", v_drop."credit_currency"), "credit_block" = coalesce(x."credit_block", v_drop."credit_block"), "language" = coalesce(x."language", v_drop."language"), "supplier_status" = coalesce(x."supplier_status", v_drop."supplier_status"), "updated_at" = now()
  where x."id" = merge_companies.keep;
  insert into "better_supabase"."company_people" ("tenant_id", "company_id", "person_id", "role", "is_primary")
  select l."tenant_id", merge_companies.keep, l."person_id", l."role", false
  from "better_supabase"."company_people" l where l."company_id" = merge_companies.drop
  on conflict do nothing;
  delete from "better_supabase"."company_people" l where l."company_id" = merge_companies.drop;
  update "better_supabase"."companies" x set "roles" = array(select distinct r from unnest(x."roles" || v_drop."roles") r order by 1) where x."id" = merge_companies.keep;
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
  return (select to_jsonb(x) || jsonb_build_object('roles', x."roles", 'customer_terms_id', x."customer_terms_id", 'supplier_terms_id', x."supplier_terms_id", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'credit_block', x."credit_block", 'supplier_status', x."supplier_status", 'language', x."language") from "better_supabase"."companies" x where x."id" = merge_companies.keep);
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
  update "better_supabase"."people" x set "email" = coalesce(x."email", v_drop."email"), "phone" = coalesce(x."phone", v_drop."phone"), "title" = coalesce(x."title", v_drop."title"), "owner_id" = coalesce(x."owner_id", v_drop."owner_id"), "user_id" = coalesce(x."user_id", v_drop."user_id"), "customer_terms_id" = coalesce(x."customer_terms_id", v_drop."customer_terms_id"), "supplier_terms_id" = coalesce(x."supplier_terms_id", v_drop."supplier_terms_id"), "credit_limit" = coalesce(x."credit_limit", v_drop."credit_limit"), "credit_currency" = coalesce(x."credit_currency", v_drop."credit_currency"), "credit_block" = coalesce(x."credit_block", v_drop."credit_block"), "language" = coalesce(x."language", v_drop."language"), "supplier_status" = coalesce(x."supplier_status", v_drop."supplier_status"), "updated_at" = now()
  where x."id" = merge_people.keep;
  insert into "better_supabase"."company_people" ("tenant_id", "company_id", "person_id", "role", "is_primary")
  select l."tenant_id", l."company_id", merge_people.keep, l."role", false
  from "better_supabase"."company_people" l where l."person_id" = merge_people.drop
  on conflict do nothing;
  delete from "better_supabase"."company_people" l where l."person_id" = merge_people.drop;
  update "better_supabase"."people" x set "roles" = array(select distinct r from unnest(x."roles" || v_drop."roles") r order by 1) where x."id" = merge_people.keep;
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
  return (select to_jsonb(x) || jsonb_build_object('roles', x."roles", 'customer_terms_id', x."customer_terms_id", 'supplier_terms_id', x."supplier_terms_id", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'credit_block', x."credit_block", 'supplier_status', x."supplier_status", 'language', x."language") from "better_supabase"."people" x where x."id" = merge_people.keep);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.move_booking (
  booking   uuid,
  starts_at timestamp with time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_old "better_supabase"."bookings"%rowtype;
  v_booking "better_supabase"."bookings"%rowtype;
  v_capacity integer;
  v_length interval;
  v_before interval;
  v_after interval;
  v_moved boolean := false;
  v_calendar uuid;
  v_tz text;
  v_title text;
  v_event uuid;
begin
  select * into v_old from "better_supabase"."bookings" bk where bk."id" = move_booking.booking for update;
  if not found then
    raise exception 'booking not found' using errcode = 'P0002', hint = 'BOOKING_NOT_FOUND';
  end if;
  if v_old."status" = 'cancelled' then
    raise exception 'a cancelled booking can''t move' using errcode = '22023', hint = 'BOOKING_STATUS_INVALID';
  end if;
  v_booking := v_old;
  if lower(v_old."during") = move_booking.starts_at then
    return jsonb_build_object('id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id", 'seat', v_booking."seat", 'startsAt', lower(v_booking."during"), 'endsAt', upper(v_booking."during"), 'status', v_booking."status", 'holdExpiresAt', v_booking."hold_expires_at", 'customerName', v_booking."customer_name", 'customerEmail', v_booking."customer_email", 'customerUserId', v_booking."customer_id", 'notes', v_booking."notes", 'seriesId', v_booking."series_id", 'createdAt', v_booking."created_at", 'cancelledAt', v_booking."cancelled_at", 'cancelReason', v_booking."cancel_reason");
  end if;
  v_length := upper(v_old."during") - lower(v_old."during");
  v_before := lower(v_old."during") - lower(v_old."blocked");
  v_after := upper(v_old."blocked") - upper(v_old."during");
  update "better_supabase"."bookings" bk set "status" = 'cancelled', "hold_expires_at" = null, "cancelled_at" = now(), "cancel_reason" = 'bs:moving'
  where bk."id" = v_old."id";
  if not exists (
    select 1 from "better_supabase"."booking_slots"(v_old."service_id", move_booking.starts_at, move_booking.starts_at + v_length, null, v_old."resource_id") t
    where t.starts_at = move_booking.starts_at
  ) then
    raise exception 'that time is not an open slot' using errcode = '23P01', hint = 'BOOKING_SLOT_UNAVAILABLE';
  end if;
  select rs."capacity" into v_capacity from "better_supabase"."booking_resources" rs where rs."id" = v_old."resource_id";
  for v_seat in 1..v_capacity loop
    begin
      update "better_supabase"."bookings" bk set "status" = v_old."status", "hold_expires_at" = v_old."hold_expires_at", "cancelled_at" = null, "cancel_reason" = null,
        "seat" = v_seat,
        "during" = tstzrange(move_booking.starts_at, move_booking.starts_at + v_length),
        "blocked" = tstzrange(move_booking.starts_at - v_before, move_booking.starts_at + v_length + v_after),
        "updated_at" = now()
      where bk."id" = v_old."id"
      returning * into v_booking;
      v_moved := true;
      exit;
    exception when exclusion_violation then
      null;
    end;
  end loop;
  if not v_moved then
    raise exception 'that time was just taken' using errcode = '23P01', hint = 'BOOKING_SLOT_UNAVAILABLE';
  end if;
  if v_booking."status" = 'confirmed' then
    if v_old."calendar_event_id" is not null then
    delete from "better_supabase"."calendar_events" where "id" = v_old."calendar_event_id";
  end if;
    delete from "better_supabase"."reminders" where "subject_type" = 'booking' and "subject_id" = v_booking."id"::text;
  delete from "better_supabase"."recurrence_rules" where "subject_type" = 'booking' and "subject_id" = v_booking."id"::text;
    select r."calendar_id", r."tz", sv."name" into v_calendar, v_tz, v_title
  from "better_supabase"."booking_resources" r join "better_supabase"."booking_services" sv on sv."id" = v_booking."service_id"
  where r."id" = v_booking."resource_id";
  if v_calendar is not null then
    insert into "better_supabase"."calendar_events" ("tenant_id", "calendar_id", "uid", "title", "starts_at", "ends_at", "tz", "status", "subject_type", "subject_id")
    values (v_booking."tenant_id", v_calendar, 'booking-' || v_booking."id"::text, coalesce(v_booking."customer_name", v_title), lower(v_booking."during"), upper(v_booking."during"), v_tz, 'confirmed', 'booking', v_booking."id"::text)
    on conflict ("calendar_id", "uid", "original_starts_at") do update set "starts_at" = excluded."starts_at", "ends_at" = excluded."ends_at"
    returning "id" into v_event;
    update "better_supabase"."bookings" set "calendar_event_id" = v_event where "id" = v_booking."id";
  end if;
    delete from "better_supabase"."reminders" where "subject_type" = 'booking' and "subject_id" = v_booking."id"::text;
  delete from "better_supabase"."recurrence_rules" where "subject_type" = 'booking' and "subject_id" = v_booking."id"::text;
  insert into "better_supabase"."recurrence_rules" ("tenant_id", "subject_type", "subject_id", "dtstart", "tzid", "rrule")
  select v_booking."tenant_id", 'booking', v_booking."id"::text, lower(v_booking."during"), r."tz", 'FREQ=DAILY;COUNT=1'
  from "better_supabase"."booking_resources" r where r."id" = v_booking."resource_id";
  insert into "better_supabase"."reminders" ("tenant_id", "subject_type", "subject_id", "user_id", "offset_minutes")
  select v_booking."tenant_id", 'booking', v_booking."id"::text, v_booking."customer_id", o
  from "better_supabase"."booking_services" sv, unnest(sv."reminder_offsets") o
  where sv."id" = v_booking."service_id";
  end if;
  perform "better_supabase".emit_event('booking.rescheduled', jsonb_build_object('organizationId', v_booking."tenant_id", 'id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id"), 'bookings/' || v_booking."id"::text, (v_booking."tenant_id")::text, null, 'better-supabase/bookings');
  return jsonb_build_object('id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id", 'seat', v_booking."seat", 'startsAt', lower(v_booking."during"), 'endsAt', upper(v_booking."during"), 'status', v_booking."status", 'holdExpiresAt', v_booking."hold_expires_at", 'customerName', v_booking."customer_name", 'customerEmail', v_booking."customer_email", 'customerUserId', v_booking."customer_id", 'notes', v_booking."notes", 'seriesId', v_booking."series_id", 'createdAt', v_booking."created_at", 'cancelledAt', v_booking."cancelled_at", 'cancelReason', v_booking."cancel_reason");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.my_passes()
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'kind', x."kind", 'holderUserId', x."holder_id", 'holderName', x."holder_name", 'holderEmail', x."holder_email", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'bookingId', x."booking_id", 'resourceId', x."resource_id", 'usesAllowed', x."uses_allowed", 'uses', x."uses", 'validFrom', x."starts_at", 'validUntil', x."expires_at", 'status', x."status", 'issuedBy', x."issued_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'revokedAt', x."revoked_at") || jsonb_build_object('nonce', x."nonce") order by x."starts_at", x."id"), '[]'::jsonb)
  from "better_supabase"."passes" x
  where x."holder_id" = auth.uid()
    and x."status" = 'active'
    and (x."expires_at" is null or x."expires_at" > now())
    and not better_supabase.tenant_disabled(x."tenant_id")
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
    select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) as value, x."due_at" as due, x."id" as id
    from "better_supabase"."activities" x
    where x."tenant_id" = open_activities.tenant
      and x."owner_id" = coalesce(open_activities.owner, auth.uid())
      and x."done_at" is null
      and (open_activities.due_before is null or x."due_at" < open_activities.due_before)
    order by x."due_at" nulls last, x."id"
    limit least(greatest(coalesce(open_activities.page_size, 50), 1), 200)
  ) p
$function$;

CREATE OR REPLACE FUNCTION better_supabase.open_appraisal_cycle (
  cycle_id    uuid,
  assignments jsonb DEFAULT '[]'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_cycle "better_supabase"."appraisal_cycles";
  v_appraisal "better_supabase"."appraisals";
  v_item jsonb;
  v_subject uuid;
  v_manager uuid;
  v_peer text;
  v_peers uuid[];
  v_version integer;
  v_steps text[];
  v_made integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_cycle from "better_supabase"."appraisal_cycles" x where x."id" = open_appraisal_cycle.cycle_id for update;
  if not found then
    raise exception 'no such review cycle' using errcode = 'P0002', hint = 'APPRAISALS_CYCLE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_cycle."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_cycle."tenant_id", 'appraisals.manage'), false))) then
    raise exception 'not allowed to manage review cycles' using errcode = '42501', hint = 'APPRAISALS_FORBIDDEN';
  end if;
  if v_cycle."status" = 'closed' then
    raise exception 'a closed cycle can''t be opened again' using errcode = '55000', hint = 'APPRAISALS_STATE';
  end if;
  if jsonb_typeof(open_appraisal_cycle.assignments) is distinct from 'array' then
    raise exception 'assignments must be a list' using errcode = '22023', hint = 'APPRAISALS_INVALID';
  end if;
  for v_item in select e from jsonb_array_elements(open_appraisal_cycle.assignments) e loop
    begin
      v_subject := (v_item ->> 'subjectUserId')::uuid;
      v_manager := nullif(v_item ->> 'managerId', '')::uuid;
      v_peers := '{}';
      if v_item ? 'peerIds' then
        for v_peer in select p from jsonb_array_elements_text(v_item -> 'peerIds') p loop
          v_peers := v_peers || v_peer::uuid;
        end loop;
      end if;
    exception when invalid_text_representation or invalid_parameter_value or null_value_not_allowed then
      raise exception 'subjectUserId, managerId and peerIds are user ids' using errcode = '22023', hint = 'APPRAISALS_INVALID';
    end;
    if v_subject is null then
      raise exception 'an assignment needs a subjectUserId' using errcode = '22023', hint = 'APPRAISALS_INVALID';
    end if;
    if v_manager = v_subject then
      raise exception 'a person can''t be their own manager' using errcode = '22023', hint = 'APPRAISALS_INVALID';
    end if;
    if v_subject = any(v_peers) or v_manager = any(v_peers) then
      raise exception 'a peer is neither the person nor the manager' using errcode = '22023', hint = 'APPRAISALS_INVALID';
    end if;
    insert into "better_supabase"."appraisals" ("tenant_id", "cycle_id", "appraisee_id", "manager_id")
    values (v_cycle."tenant_id", v_cycle."id", v_subject, v_manager)
    on conflict do nothing
    returning * into v_appraisal;
    if v_appraisal."id" is not null then
      v_made := v_made + 1;
      insert into "better_supabase"."appraisal_reviews" ("tenant_id", "appraisal_id", "reviewer_id", "kind")
      values (v_appraisal."tenant_id", v_appraisal."id", v_subject, 'self');
      if v_manager is not null then
        insert into "better_supabase"."appraisal_reviews" ("tenant_id", "appraisal_id", "reviewer_id", "kind")
        values (v_appraisal."tenant_id", v_appraisal."id", v_manager, 'manager');
      end if;
      insert into "better_supabase"."appraisal_reviews" ("tenant_id", "appraisal_id", "reviewer_id", "kind")
      select distinct v_appraisal."tenant_id", v_appraisal."id", p, 'peer' from unnest(v_peers) p;
      if v_cycle."program" is not null then
        select x."version", array(select s ->> 'id' from jsonb_array_elements(x."steps") s)
        into v_version, v_steps
        from "better_supabase"."enrollment_programs" x
        where x."tenant_id" = v_cycle."tenant_id" and x."key" = v_cycle."program";
        perform "better_supabase"."enrollment_ensure"(v_cycle."tenant_id", v_cycle."program", v_version, v_steps,
          'appraisal', v_appraisal."id"::text, auth.uid());
      end if;
      perform "better_supabase".emit_event('appraisal.created', jsonb_build_object('organizationId', v_appraisal."tenant_id", 'id', v_appraisal."id", 'cycleId', v_appraisal."cycle_id", 'subjectUserId', v_appraisal."appraisee_id", 'status', v_appraisal."status"), 'appraisals/' || v_appraisal."id"::text, (v_appraisal."tenant_id")::text, null, 'better-supabase/appraisals');
  perform better_supabase.audit_event(
    event_type => 'appraisal.created',
    category => 'data',
    target_type => 'appraisal',
    record_id => v_appraisal."id"::text,
    summary => 'appraisal created',
    tenant => (v_appraisal."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_appraisal."tenant_id", 'id', v_appraisal."id", 'cycleId', v_appraisal."cycle_id", 'subjectUserId', v_appraisal."appraisee_id", 'status', v_appraisal."status")
  );
    end if;
    v_appraisal := null;
  end loop;
  update "better_supabase"."appraisal_cycles" x set "status" = 'open', "opened_at" = coalesce(x."opened_at", now())
  where x."id" = v_cycle."id"
  returning * into v_cycle;
  if v_made > 0 or v_cycle."opened_at" = now() then
    perform "better_supabase".emit_event('appraisal_cycle.opened', jsonb_build_object('organizationId', v_cycle."tenant_id", 'id', v_cycle."id", 'name', v_cycle."name", 'status', v_cycle."status"), 'appraisal-cycles/' || v_cycle."id"::text, (v_cycle."tenant_id")::text, null, 'better-supabase/appraisals');
  perform better_supabase.audit_event(
    event_type => 'appraisal_cycle.opened',
    category => 'data',
    target_type => 'appraisal_cycle',
    record_id => v_cycle."id"::text,
    target_label => v_cycle."name",
    summary => 'review cycle opened',
    tenant => (v_cycle."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_cycle."tenant_id", 'id', v_cycle."id", 'name', v_cycle."name", 'status', v_cycle."status")
  );
  end if;
  return jsonb_build_object('id', v_cycle."id", 'organizationId', v_cycle."tenant_id", 'name', v_cycle."name", 'startsOn', v_cycle."starts_on", 'endsOn', v_cycle."ends_on", 'program', v_cycle."program", 'status', v_cycle."status", 'anonymity', v_cycle."anonymity", 'shareFeedback', v_cycle."share_feedback", 'openedAt', v_cycle."opened_at", 'closedAt', v_cycle."closed_at", 'createdAt', v_cycle."created_at", 'competencies', coalesce((select jsonb_agg(jsonb_build_object('key', w."key", 'name', w."name", 'weight', w."weight") order by w."position") from "better_supabase"."appraisal_competencies" w where w."cycle_id" = v_cycle."id"), '[]'::jsonb)) || jsonb_build_object('appraisalsCreated', v_made);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.open_enrollment_steps (
  tenant        uuid,
  assignee_role text                     DEFAULT NULL::text,
  assignee_user uuid                     DEFAULT NULL::uuid,
  due_before    timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  page_size     integer                  DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_read boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (open_enrollment_steps.tenant is not null and coalesce(better_supabase.can('tenant', open_enrollment_steps.tenant, 'enrollments.read'), false)));
begin
  if not v_read and auth.uid() is null then
    raise exception 'not allowed to read enrollments' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'id', o.row_id, 'organizationId', o.scope_id, 'program', o.program,
      'subjectType', o.subject_type, 'subjectId', o.subject_id, 'step', o.step, 'title', o.title,
      'assignee', o.assignee, 'dueAt', o.due_at
    )) order by o.due_at nulls last, o.row_id, o.step)
    from (
      select x."id" as row_id, x."tenant_id" as scope_id, x."program" as program,
        x."subject_type" as subject_type, x."subject_id" as subject_id, y."step" as step,
        case when y."assignee_role" is not null then jsonb_build_object('role', y."assignee_role") when y."assignee_id" is not null then jsonb_build_object('userId', y."assignee_id") end as assignee, y."due_at" as due_at,
        (select t.value ->> 'title' from "better_supabase"."enrollment_programs" q, jsonb_array_elements(q."steps") as t(value)
          where q."tenant_id" = x."tenant_id" and q."key" = x."program" and t.value ->> 'id' = y."step" limit 1) as title
      from "better_supabase"."enrollment_steps" y
      join "better_supabase"."enrollments" x on x."id" = y."enrollment_id"
      where y."tenant_id" = open_enrollment_steps.tenant and x."tenant_id" = open_enrollment_steps.tenant
        and y."completed_at" is null and x."status" = 'active'
        -- A sequence's open step is its next run, which its runner takes.
        and x."program" not like 'sequence:%'
        and (v_read or y."assignee_id" = auth.uid())
        and (open_enrollment_steps.assignee_role is null or y."assignee_role" = open_enrollment_steps.assignee_role)
        and (open_enrollment_steps.assignee_user is null or y."assignee_id" = open_enrollment_steps.assignee_user)
        and (open_enrollment_steps.due_before is null or y."due_at" < open_enrollment_steps.due_before)
      order by y."due_at" nulls last, x."id", y."step"
      limit least(greatest(coalesce(open_enrollment_steps.page_size, 50), 1), 200)
    ) o
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.pipeline_board (
  subject_type text,
  pipeline     uuid,
  owner        uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
begin
  case pipeline_board.subject_type
    when 'deal' then
      return (
        with rows as (
          select r."stage_id" as stage_id, r."currency"::text as currency, r."amount"::bigint as amount,
            r."amount" * coalesce(r."probability", st."probability", 0) / 100.0 as weighted
          from "better_supabase"."deals" r
          join "better_supabase"."pipeline_stages" st on st."id" = r."stage_id"
          where r."pipeline_id" = pipeline_board.pipeline and r."archived_at" is null and (pipeline_board.owner is null or r."owner_id" = pipeline_board.owner)
        ),
        counts as (select stage_id, count(*) as n from rows group by stage_id),
        sums as (
          select stage_id, jsonb_agg(jsonb_build_object('currency', currency, 'amount', amount::text, 'weighted', round(weighted)::bigint::text) order by currency) as totals
          from (select stage_id, currency, coalesce(sum(amount), 0) as amount, coalesce(sum(weighted), 0) as weighted from rows where currency is not null group by stage_id, currency) x
          group by stage_id
        )
        select coalesce(jsonb_agg(jsonb_build_object(
          'stageId', st."id", 'key', st."key", 'name', st."name", 'color', st."color", 'icon', st."icon",
          'category', st."category", 'outcome', st."outcome", 'probability', st."probability",
          'wipLimit', st."wip_limit", 'count', coalesce(n.n, 0),
          'overLimit', st."wip_limit" is not null and coalesce(n.n, 0) > st."wip_limit",
          'totals', coalesce(m.totals, '[]'::jsonb)
        ) order by st."rank" collate "C"), '[]'::jsonb)
        from "better_supabase"."pipeline_stages" st
        left join counts n on n.stage_id = st."id"
        left join sums m on m.stage_id = st."id"
        where st."pipeline_id" = pipeline_board.pipeline and st."archived_at" is null
      );
    when 'work_item' then
      return (
        with rows as (
          select r."stage_id" as stage_id, null::text as currency, null::bigint as amount, null::numeric as weighted
          from "better_supabase"."work_items" r
          join "better_supabase"."pipeline_stages" st on st."id" = r."stage_id"
          where r."pipeline_id" = pipeline_board.pipeline and r."archived_at" is null
        ),
        counts as (select stage_id, count(*) as n from rows group by stage_id),
        sums as (
          select stage_id, jsonb_agg(jsonb_build_object('currency', currency, 'amount', amount::text, 'weighted', round(weighted)::bigint::text) order by currency) as totals
          from (select stage_id, currency, coalesce(sum(amount), 0) as amount, coalesce(sum(weighted), 0) as weighted from rows where currency is not null group by stage_id, currency) x
          group by stage_id
        )
        select coalesce(jsonb_agg(jsonb_build_object(
          'stageId', st."id", 'key', st."key", 'name', st."name", 'color', st."color", 'icon', st."icon",
          'category', st."category", 'outcome', st."outcome", 'probability', st."probability",
          'wipLimit', st."wip_limit", 'count', coalesce(n.n, 0),
          'overLimit', st."wip_limit" is not null and coalesce(n.n, 0) > st."wip_limit",
          'totals', coalesce(m.totals, '[]'::jsonb)
        ) order by st."rank" collate "C"), '[]'::jsonb)
        from "better_supabase"."pipeline_stages" st
        left join counts n on n.stage_id = st."id"
        left join sums m on m.stage_id = st."id"
        where st."pipeline_id" = pipeline_board.pipeline and st."archived_at" is null
      );
    when 'maintenance_request' then
      return (
        with rows as (
          select r."stage_id" as stage_id, null::text as currency, null::bigint as amount, null::numeric as weighted
          from "better_supabase"."maintenance_requests" r
          join "better_supabase"."pipeline_stages" st on st."id" = r."stage_id"
          where r."pipeline_id" = pipeline_board.pipeline
        ),
        counts as (select stage_id, count(*) as n from rows group by stage_id),
        sums as (
          select stage_id, jsonb_agg(jsonb_build_object('currency', currency, 'amount', amount::text, 'weighted', round(weighted)::bigint::text) order by currency) as totals
          from (select stage_id, currency, coalesce(sum(amount), 0) as amount, coalesce(sum(weighted), 0) as weighted from rows where currency is not null group by stage_id, currency) x
          group by stage_id
        )
        select coalesce(jsonb_agg(jsonb_build_object(
          'stageId', st."id", 'key', st."key", 'name', st."name", 'color', st."color", 'icon', st."icon",
          'category', st."category", 'outcome', st."outcome", 'probability', st."probability",
          'wipLimit', st."wip_limit", 'count', coalesce(n.n, 0),
          'overLimit', st."wip_limit" is not null and coalesce(n.n, 0) > st."wip_limit",
          'totals', coalesce(m.totals, '[]'::jsonb)
        ) order by st."rank" collate "C"), '[]'::jsonb)
        from "better_supabase"."pipeline_stages" st
        left join counts n on n.stage_id = st."id"
        left join sums m on m.stage_id = st."id"
        where st."pipeline_id" = pipeline_board.pipeline and st."archived_at" is null
      );
    when 'application' then
      return (
        with rows as (
          select r."stage_id" as stage_id, null::text as currency, null::bigint as amount, null::numeric as weighted
          from "better_supabase"."applications" r
          join "better_supabase"."pipeline_stages" st on st."id" = r."stage_id"
          where r."pipeline_id" = pipeline_board.pipeline and (pipeline_board.owner is null or r."owner_id" = pipeline_board.owner)
        ),
        counts as (select stage_id, count(*) as n from rows group by stage_id),
        sums as (
          select stage_id, jsonb_agg(jsonb_build_object('currency', currency, 'amount', amount::text, 'weighted', round(weighted)::bigint::text) order by currency) as totals
          from (select stage_id, currency, coalesce(sum(amount), 0) as amount, coalesce(sum(weighted), 0) as weighted from rows where currency is not null group by stage_id, currency) x
          group by stage_id
        )
        select coalesce(jsonb_agg(jsonb_build_object(
          'stageId', st."id", 'key', st."key", 'name', st."name", 'color', st."color", 'icon', st."icon",
          'category', st."category", 'outcome', st."outcome", 'probability', st."probability",
          'wipLimit', st."wip_limit", 'count', coalesce(n.n, 0),
          'overLimit', st."wip_limit" is not null and coalesce(n.n, 0) > st."wip_limit",
          'totals', coalesce(m.totals, '[]'::jsonb)
        ) order by st."rank" collate "C"), '[]'::jsonb)
        from "better_supabase"."pipeline_stages" st
        left join counts n on n.stage_id = st."id"
        left join sums m on m.stage_id = st."id"
        where st."pipeline_id" = pipeline_board.pipeline and st."archived_at" is null
      );
    when 'case' then
      return (
        with rows as (
          select r."stage_id" as stage_id, null::text as currency, null::bigint as amount, null::numeric as weighted
          from "better_supabase"."cases" r
          join "better_supabase"."pipeline_stages" st on st."id" = r."stage_id"
          where r."pipeline_id" = pipeline_board.pipeline and r."archived_at" is null
        ),
        counts as (select stage_id, count(*) as n from rows group by stage_id),
        sums as (
          select stage_id, jsonb_agg(jsonb_build_object('currency', currency, 'amount', amount::text, 'weighted', round(weighted)::bigint::text) order by currency) as totals
          from (select stage_id, currency, coalesce(sum(amount), 0) as amount, coalesce(sum(weighted), 0) as weighted from rows where currency is not null group by stage_id, currency) x
          group by stage_id
        )
        select coalesce(jsonb_agg(jsonb_build_object(
          'stageId', st."id", 'key', st."key", 'name', st."name", 'color', st."color", 'icon', st."icon",
          'category', st."category", 'outcome', st."outcome", 'probability', st."probability",
          'wipLimit', st."wip_limit", 'count', coalesce(n.n, 0),
          'overLimit', st."wip_limit" is not null and coalesce(n.n, 0) > st."wip_limit",
          'totals', coalesce(m.totals, '[]'::jsonb)
        ) order by st."rank" collate "C"), '[]'::jsonb)
        from "better_supabase"."pipeline_stages" st
        left join counts n on n.stage_id = st."id"
        left join sums m on m.stage_id = st."id"
        where st."pipeline_id" = pipeline_board.pipeline and st."archived_at" is null
      );
    else
      raise exception 'this subject type has no pipeline binding' using errcode = '22023', hint = 'PIPELINE_SUBJECT_UNKNOWN';
  end case;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.place_booking (
  service       uuid,
  resource      uuid,
  starts_at     timestamp with time zone,
  customer      jsonb,
  confirm       boolean,
  customer_user uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_customer jsonb := coalesce(place_booking.customer, '{}'::jsonb);
  v_service "better_supabase"."booking_services"%rowtype;
  v_capacity integer;
  v_during tstzrange;
  v_blocked tstzrange;
  v_status text := case when coalesce(place_booking.confirm, false) then 'confirmed' else 'hold' end;
  v_expires timestamptz;
  v_token text := encode(extensions.gen_random_bytes(24), 'hex');
  v_id uuid;
  v_seat integer;
  v_booking "better_supabase"."bookings"%rowtype;
  v_calendar uuid;
  v_tz text;
  v_title text;
  v_event uuid;
begin
  select * into v_service from "better_supabase"."booking_services" sv where sv."id" = place_booking.service and sv."active";
  if not found then
    raise exception 'service not found' using errcode = 'P0002', hint = 'BOOKING_SERVICE_NOT_FOUND';
  end if;
  select rs."capacity" into v_capacity from "better_supabase"."booking_resources" rs
    where rs."id" = place_booking.resource and rs."tenant_id" = v_service."tenant_id" and rs."active";
  if not found then
    raise exception 'resource not found' using errcode = 'P0002', hint = 'BOOKING_RESOURCE_NOT_FOUND';
  end if;
  v_during := tstzrange(place_booking.starts_at, place_booking.starts_at + v_service."duration");
  v_blocked := tstzrange(place_booking.starts_at - v_service."buffer_before", upper(v_during) + v_service."buffer_after");
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_booking_reserve"(uuid, uuid, uuid, tstzrange, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::uuid, $4::tstzrange, $5::jsonb)', v_hook::oid::regproc)
        using v_service."tenant_id", place_booking.service, place_booking.resource, v_during, v_customer;
    end if;
  end;
  perform "better_supabase"."expire_booking_holds_in"(place_booking.resource, v_blocked);
  if not exists (
    select 1 from "better_supabase"."booking_slots"(place_booking.service, place_booking.starts_at, upper(v_during), null, place_booking.resource) t
    where t.starts_at = place_booking.starts_at
  ) then
    raise exception 'that time is not an open slot' using errcode = '23P01', hint = 'BOOKING_SLOT_UNAVAILABLE';
  end if;
  if v_status = 'hold' then
    v_expires := now() + v_service."hold_for";
  end if;
  for v_seat in 1..v_capacity loop
    begin
      insert into "better_supabase"."bookings" ("tenant_id", "resource_id", "service_id", "seat", "during", "blocked", "status", "hold_expires_at", "customer_name", "customer_email", "customer_id", "notes", "access_hash", "created_by")
      values (v_service."tenant_id", place_booking.resource, place_booking.service, v_seat, v_during, v_blocked, v_status, v_expires, v_customer ->> 'name', lower(v_customer ->> 'email'), place_booking.customer_user, v_customer ->> 'notes', encode(extensions.digest(convert_to(v_token, 'utf8'), 'sha256'), 'hex'), auth.uid())
      returning * into v_booking;
      v_id := v_booking."id";
      exit;
    exception when exclusion_violation then
      null;
    end;
  end loop;
  if v_id is null then
    raise exception 'that time was just taken' using errcode = '23P01', hint = 'BOOKING_SLOT_UNAVAILABLE';
  end if;
  perform "better_supabase".emit_event('booking.reserved', jsonb_build_object('organizationId', v_booking."tenant_id", 'id', v_id, 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id"), 'bookings/' || v_id::text, (v_booking."tenant_id")::text, null, 'better-supabase/bookings');
  if v_status = 'confirmed' then
    select r."calendar_id", r."tz", sv."name" into v_calendar, v_tz, v_title
  from "better_supabase"."booking_resources" r join "better_supabase"."booking_services" sv on sv."id" = v_booking."service_id"
  where r."id" = v_booking."resource_id";
  if v_calendar is not null then
    insert into "better_supabase"."calendar_events" ("tenant_id", "calendar_id", "uid", "title", "starts_at", "ends_at", "tz", "status", "subject_type", "subject_id")
    values (v_booking."tenant_id", v_calendar, 'booking-' || v_booking."id"::text, coalesce(v_booking."customer_name", v_title), lower(v_booking."during"), upper(v_booking."during"), v_tz, 'confirmed', 'booking', v_booking."id"::text)
    on conflict ("calendar_id", "uid", "original_starts_at") do update set "starts_at" = excluded."starts_at", "ends_at" = excluded."ends_at"
    returning "id" into v_event;
    update "better_supabase"."bookings" set "calendar_event_id" = v_event where "id" = v_booking."id";
  end if;
    delete from "better_supabase"."reminders" where "subject_type" = 'booking' and "subject_id" = v_booking."id"::text;
  delete from "better_supabase"."recurrence_rules" where "subject_type" = 'booking' and "subject_id" = v_booking."id"::text;
  insert into "better_supabase"."recurrence_rules" ("tenant_id", "subject_type", "subject_id", "dtstart", "tzid", "rrule")
  select v_booking."tenant_id", 'booking', v_booking."id"::text, lower(v_booking."during"), r."tz", 'FREQ=DAILY;COUNT=1'
  from "better_supabase"."booking_resources" r where r."id" = v_booking."resource_id";
  insert into "better_supabase"."reminders" ("tenant_id", "subject_type", "subject_id", "user_id", "offset_minutes")
  select v_booking."tenant_id", 'booking', v_booking."id"::text, v_booking."customer_id", o
  from "better_supabase"."booking_services" sv, unnest(sv."reminder_offsets") o
  where sv."id" = v_booking."service_id";
    perform "better_supabase".emit_event('booking.confirmed', jsonb_build_object('organizationId', v_booking."tenant_id", 'id', v_id, 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id"), 'bookings/' || v_id::text, (v_booking."tenant_id")::text, null, 'better-supabase/bookings');
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_booking_confirm"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  end if;
  if v_status = 'hold' then
    perform "better_supabase"."enqueue_job"(queue => 'bookings.expire-holds', payload => jsonb_build_object('bookingId', v_id), delay => ceil(extract(epoch from (v_expires - now())))::integer + 1, dedupe_key => 'bookings:expire:' || v_id::text, dedupe_running => false);
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_booking_reserve"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return jsonb_build_object('id', v_booking."id", 'resourceId', v_booking."resource_id", 'serviceId', v_booking."service_id", 'seat', v_booking."seat", 'startsAt', lower(v_booking."during"), 'endsAt', upper(v_booking."during"), 'status', v_booking."status", 'holdExpiresAt', v_booking."hold_expires_at", 'customerName', v_booking."customer_name", 'customerEmail', v_booking."customer_email", 'customerUserId', v_booking."customer_id", 'notes', v_booking."notes", 'seriesId', v_booking."series_id", 'createdAt', v_booking."created_at", 'cancelledAt', v_booking."cancelled_at", 'cancelReason', v_booking."cancel_reason") || jsonb_build_object('accessToken', v_token);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.qualify_referral (
  tenant        uuid,
  referred_user uuid DEFAULT NULL::uuid,
  referred_org  uuid DEFAULT NULL::uuid,
  source        text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_ref "better_supabase"."referrals";
  v_tx uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (qualify_referral.tenant is not null and coalesce(better_supabase.can('tenant', qualify_referral.tenant, 'referrals.manage'), false))) then
    raise exception 'not allowed to qualify referrals' using errcode = '42501', hint = 'REFERRAL_FORBIDDEN';
  end if;
  select * into v_ref from "better_supabase"."referrals" x
  where x."tenant_id" = qualify_referral.tenant
    and ((qualify_referral.referred_user is not null and x."referred_id" = qualify_referral.referred_user)
      or (qualify_referral.referred_org is not null and x."referred_organization_id" = qualify_referral.referred_org))
  for update;
  if not found then
    return null;
  end if;
  if v_ref."status" <> 'attributed' then
    return jsonb_build_object('id', v_ref."id", 'organizationId', v_ref."tenant_id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_id", 'referredOrganizationId', v_ref."referred_organization_id", 'referredEmail', v_ref."referred_email", 'status', v_ref."status", 'rewardAmount', v_ref."reward_amount"::text, 'rewardUnit', v_ref."reward_unit", 'qualifiedAt', v_ref."qualified_at", 'rewardedAt', v_ref."rewarded_at", 'ledgerTransactionId', v_ref."ledger_transaction_id", 'createdAt', v_ref."created_at");
  end if;
  update "better_supabase"."referrals" x set "status" = 'qualified', "qualified_at" = now(), "qualified_by" = left(qualify_referral.source, 200)
  where x."id" = v_ref."id" returning * into v_ref;
  perform "better_supabase".emit_event('referral.qualified', jsonb_build_object('organizationId', v_ref."tenant_id", 'id', v_ref."id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_id", 'referredOrganizationId', v_ref."referred_organization_id", 'status', v_ref."status"), 'referrals/' || v_ref."id"::text, (v_ref."tenant_id")::text, null, 'better-supabase/referrals');
  perform better_supabase.audit_event(
    event_type => 'referral.qualified',
    category => 'data',
    target_type => 'referral',
    record_id => v_ref."id"::text,
    summary => 'referral qualified',
    tenant => (v_ref."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_ref."tenant_id", 'id', v_ref."id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_id", 'referredOrganizationId', v_ref."referred_organization_id", 'status', v_ref."status")
  );
  if v_ref."reward_amount" > 0 then
    v_tx := "better_supabase"."ledger_post"(v_ref."tenant_id", 'referral.reward',
      jsonb_build_array(
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_ref."tenant_id", 'expense', 'referrals:expense:' || v_ref."reward_unit", 'Referral rewards', v_ref."reward_unit", 0::smallint, null, null, null, true, 'referrals.read', 'referrals', null), 'amount', (-v_ref."reward_amount")::text),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_ref."tenant_id", 'payable', 'referrals:rewards:' || v_ref."referrer_id"::text || ':' || v_ref."reward_unit", 'Referral rewards payable', v_ref."reward_unit", 0::smallint, null, null, v_ref."referrer_id", true, 'referrals.read', 'referrals', null), 'amount', v_ref."reward_amount"::text)),
      'referrals', v_ref."id"::text, null, 'referral:' || v_ref."id"::text, null,
      jsonb_build_object('referrerId', v_ref."referrer_id"));
    update "better_supabase"."referrals" x set "status" = 'rewarded', "rewarded_at" = now(), "ledger_transaction_id" = v_tx
    where x."id" = v_ref."id" returning * into v_ref;
    perform "better_supabase".emit_event('referral.rewarded', jsonb_build_object('organizationId', v_ref."tenant_id", 'id', v_ref."id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_id", 'referredOrganizationId', v_ref."referred_organization_id", 'status', v_ref."status", 'amount', v_ref."reward_amount"::text, 'unit', v_ref."reward_unit"), 'referrals/' || v_ref."id"::text, (v_ref."tenant_id")::text, null, 'better-supabase/referrals');
  perform better_supabase.audit_event(
    event_type => 'referral.rewarded',
    category => 'data',
    target_type => 'referral',
    record_id => v_ref."id"::text,
    summary => 'referral rewarded',
    tenant => (v_ref."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_ref."tenant_id", 'id', v_ref."id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_id", 'referredOrganizationId', v_ref."referred_organization_id", 'status', v_ref."status", 'amount', v_ref."reward_amount"::text, 'unit', v_ref."reward_unit")
  );
  end if;
  return jsonb_build_object('id', v_ref."id", 'organizationId', v_ref."tenant_id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_id", 'referredOrganizationId', v_ref."referred_organization_id", 'referredEmail', v_ref."referred_email", 'status', v_ref."status", 'rewardAmount', v_ref."reward_amount"::text, 'rewardUnit', v_ref."reward_unit", 'qualifiedAt', v_ref."qualified_at", 'rewardedAt', v_ref."rewarded_at", 'ledgerTransactionId', v_ref."ledger_transaction_id", 'createdAt', v_ref."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.quote_from_deal (
  deal uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_deal "better_supabase"."deals";
  v_row "better_supabase"."quotes";
  v_contact record;
  v_lines jsonb;
begin
  select * into v_deal from "better_supabase"."deals" x where x."id" = quote_from_deal.deal;
  if v_deal."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_deal."tenant_id", 'quotes.write'), false)) then
    raise exception 'no such deal you can quote' using errcode = 'P0002', hint = 'QUOTE_ORIGIN_NOT_FOUND';
  end if;
  select * into v_row from "better_supabase"."quotes" x
  where x."origin_type" = 'deal' and x."origin_id" = v_deal."id"::text
  order by x."created_at" limit 1;
  if v_row."id" is not null then
    return (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'unit', ql."unit", 'discountKind', ql."discount_kind", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
  end if;
  select x."contact_type" as type, x."contact_id" as id into v_contact
  from "better_supabase"."deal_contacts" x where x."deal_id" = v_deal."id" order by x."is_primary" desc limit 1;
  select coalesce(jsonb_agg(jsonb_build_object('description', x."description", 'quantity', x."quantity", 'unitAmount', x."unit_amount"::text,
      'discountBps', x."discount_bps", 'taxRateBps', x."tax_rate_bps", 'taxCode', x."tax_code",
      'product', case when x."product_type" is null then null else jsonb_build_object('type', x."product_type", 'id', x."product_id") end
    ) order by x."position"), '[]'::jsonb) into v_lines
  from "better_supabase"."deal_lines" x where x."parent_id" = v_deal."id";
  if jsonb_array_length(v_lines) = 0 and v_deal."amount" > 0 then
    v_lines := jsonb_build_array(jsonb_build_object('description', v_deal."name", 'quantity', 1, 'unitAmount', v_deal."amount"::text));
  end if;
  return "better_supabase"."create_quote"(v_deal."tenant_id", jsonb_build_object(
    'title', v_deal."name", 'currency', v_deal."currency", 'ownerId', v_deal."owner_id",
    'company', case when v_deal."company_id" is null then null else jsonb_build_object('type', v_deal."company_type", 'id', v_deal."company_id") end,
    'contact', case when v_contact.id is null then null else jsonb_build_object('type', v_contact.type, 'id', v_contact.id) end,
    'origin', jsonb_build_object('type', 'deal', 'id', v_deal."id"::text)), v_lines);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_consent (
  subject_type        text,
  subject_id          text,
  purpose_key         text,
  status              text,
  given_by            text                     DEFAULT 'self'::text,
  given_by_contact_id uuid                     DEFAULT NULL::uuid,
  expires_at          timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  scope               jsonb                    DEFAULT '{}'::jsonb,
  evidence            jsonb                    DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_tenant uuid;
  v_purpose "better_supabase"."consent_purposes";
  v_row "better_supabase"."consents";
  v_given_by text := coalesce(record_consent.given_by, 'self');
  v_contact uuid := record_consent.given_by_contact_id;
  v_scope jsonb := coalesce(record_consent.scope, '{}'::jsonb);
  v_evidence jsonb := coalesce(record_consent.evidence, '{}'::jsonb);
  v_until timestamptz := record_consent.expires_at;
  v_signature uuid;
  v_submission uuid;
  v_attachment uuid;
  v_representative uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  v_tenant := ((case record_consent.subject_type
      when 'message' then (select s."tenant_id"::text from "better_supabase"."messages" s where s."id" = (record_consent.subject_id)::uuid)
      when 'conversation' then (select s."tenant_id"::text from "better_supabase"."conversations" s where s."id" = (record_consent.subject_id)::uuid)
      when 'channel' then (select s."tenant_id"::text from "better_supabase"."channels" s where s."id" = (record_consent.subject_id)::uuid)
      when 'company' then (select s."tenant_id"::text from "better_supabase"."companies" s where s."id" = (record_consent.subject_id)::uuid)
      when 'person' then (select s."tenant_id"::text from "better_supabase"."people" s where s."id" = (record_consent.subject_id)::uuid)
      when 'deal' then (select s."tenant_id"::text from "better_supabase"."deals" s where s."id" = (record_consent.subject_id)::uuid)
      when 'course' then (select s."tenant_id"::text from "better_supabase"."courses" s where s."id" = (record_consent.subject_id)::uuid)
      when 'post' then (select s."tenant_id"::text from "better_supabase"."posts" s where s."id" = (record_consent.subject_id)::uuid)
      when 'activity' then (select s."tenant_id"::text from "better_supabase"."activities" s where s."id" = (record_consent.subject_id)::uuid)
      when 'quote' then (select s."tenant_id"::text from "better_supabase"."quotes" s where s."id" = (record_consent.subject_id)::uuid)
      when 'work_item' then (select s."tenant_id"::text from "better_supabase"."work_items" s where s."id" = (record_consent.subject_id)::uuid)
      when 'employee' then (select s."tenant_id"::text from "better_supabase"."employees" s where s."id" = (record_consent.subject_id)::uuid)
      when 'invoice' then (select s."tenant_id"::text from "better_supabase"."invoices" s where s."id" = (record_consent.subject_id)::uuid)
      when 'ledger_account' then (select s."tenant_id"::text from "better_supabase"."ledger_accounts" s where s."id" = (record_consent.subject_id)::uuid)
      when 'product' then (select s."tenant_id"::text from "better_supabase"."products" s where s."id" = (record_consent.subject_id)::uuid)
      when 'product_variant' then (select s."tenant_id"::text from "better_supabase"."product_variants" s where s."id" = (record_consent.subject_id)::uuid)
      when 'rfq' then (select s."tenant_id"::text from "better_supabase"."rfqs" s where s."id" = (record_consent.subject_id)::uuid)
      when 'till' then (select s."tenant_id"::text from "better_supabase"."tills" s where s."id" = (record_consent.subject_id)::uuid)
      when 'order' then (select s."tenant_id"::text from "better_supabase"."orders" s where s."id" = (record_consent.subject_id)::uuid)
      when 'calendar_event' then (select s."tenant_id"::text from "better_supabase"."calendar_events" s where s."id" = (record_consent.subject_id)::uuid)
      when 'booking' then (select s."tenant_id"::text from "better_supabase"."bookings" s where s."id" = (record_consent.subject_id)::uuid)
      when 'asset' then (select s."tenant_id"::text from "better_supabase"."assets" s where s."id" = (record_consent.subject_id)::uuid)
      when 'asset_location' then (select s."tenant_id"::text from "better_supabase"."asset_locations" s where s."id" = (record_consent.subject_id)::uuid)
      when 'lease' then (select s."tenant_id"::text from "better_supabase"."leases" s where s."id" = (record_consent.subject_id)::uuid)
      when 'expense_report' then (select s."tenant_id"::text from "better_supabase"."expense_reports" s where s."id" = (record_consent.subject_id)::uuid)
      when 'expense_line' then (select s."tenant_id"::text from "better_supabase"."expense_lines" s where s."id" = (record_consent.subject_id)::uuid)
      when 'donation_fund' then (select s."tenant_id"::text from "better_supabase"."donation_funds" s where s."id" = (record_consent.subject_id)::uuid)
      when 'work_order' then (select s."tenant_id"::text from "better_supabase"."work_orders" s where s."id" = (record_consent.subject_id)::uuid)
      when 'shipment' then (select s."tenant_id"::text from "better_supabase"."shipments" s where s."id" = (record_consent.subject_id)::uuid)
      when 'contract' then (select s."tenant_id"::text from "better_supabase"."contracts" s where s."id" = (record_consent.subject_id)::uuid)
      when 'control' then (select s."tenant_id"::text from "better_supabase"."controls" s where s."id" = (record_consent.subject_id)::uuid)
      when 'compliance_policy' then (select s."tenant_id"::text from "better_supabase"."compliance_policies" s where s."id" = (record_consent.subject_id)::uuid)
      when 'qualification_type' then (select s."tenant_id"::text from "better_supabase"."qualification_types" s where s."id" = (record_consent.subject_id)::uuid)
      when 'risk' then (select s."tenant_id"::text from "better_supabase"."risks" s where s."id" = (record_consent.subject_id)::uuid)
      when 'case' then (select s."tenant_id"::text from "better_supabase"."cases" s where s."id" = (record_consent.subject_id)::uuid)
      when 'inspection' then (select s."tenant_id"::text from "better_supabase"."inspections" s where s."id" = (record_consent.subject_id)::uuid)
      when 'inspection_program' then (select s."tenant_id"::text from "better_supabase"."inspection_programs" s where s."id" = (record_consent.subject_id)::uuid)
      when 'inspection_finding' then (select s."tenant_id"::text from "better_supabase"."inspection_findings" s where s."id" = (record_consent.subject_id)::uuid)
      when 'form' then (select s."tenant_id"::text from "better_supabase"."forms" s where s."id" = (record_consent.subject_id)::uuid)
      when 'meeting' then (select s."tenant_id"::text from "better_supabase"."meetings" s where s."id" = (record_consent.subject_id)::uuid)
      when 'meeting_decision' then (select s."tenant_id"::text from "better_supabase"."meeting_decisions" s where s."id" = (record_consent.subject_id)::uuid)
      when 'maintenance_plan' then (select s."tenant_id"::text from "better_supabase"."maintenance_plans" s where s."id" = (record_consent.subject_id)::uuid)
      when 'dam_usage_right' then (select s."tenant_id"::text from "better_supabase"."dam_usage_rights" s where s."id" = (record_consent.subject_id)::uuid)
      when 'lims_sample' then (select s."tenant_id"::text from "better_supabase"."lims_samples" s where s."id" = (record_consent.subject_id)::uuid)
      when 'tax_code' then (select s."tenant_id"::text from "better_supabase"."tax_codes" s where s."id" = (record_consent.subject_id)::uuid)
      when 'production_order' then (select s."tenant_id"::text from "better_supabase"."production_orders" s where s."id" = (record_consent.subject_id)::uuid)
      when 'work_center' then (select s."tenant_id"::text from "better_supabase"."work_centers" s where s."id" = (record_consent.subject_id)::uuid)
      when 'bank_account' then (select s."tenant_id"::text from "better_supabase"."bank_accounts" s where s."id" = (record_consent.subject_id)::uuid)
      when 'care_plan' then (select s."tenant_id"::text from "better_supabase"."care_plans" s where s."id" = (record_consent.subject_id)::uuid)
      when 'incident' then (select s."tenant_id"::text from "better_supabase"."incidents" s where s."id" = (record_consent.subject_id)::uuid)
      when 'content_entry' then (select s."tenant_id"::text from "better_supabase"."content_entries" s where s."id" = (record_consent.subject_id)::uuid)
      when 'document' then (select s."tenant_id"::text from "better_supabase"."documents" s where s."id" = (record_consent.subject_id)::uuid)
      when 'customer' then (select s."organization_id"::text from "public"."customers" s where s."id" = (record_consent.subject_id)::uuid)
      when 'drive_node' then (select s."tenant_id"::text from "better_supabase"."drive_nodes" s where s."id" = (record_consent.subject_id)::uuid)
      when 'application' then (select s."tenant_id"::text from "better_supabase"."applications" s where s."id" = (record_consent.subject_id)::uuid)
      when 'change_request' then (select s."organization_id"::text from "public"."change_requests" s where s."id" = (record_consent.subject_id)::uuid)
      when 'project' then (select s."organization_id"::text from "public"."projects" s where s."id" = (record_consent.subject_id)::uuid)
      when 'task' then (select s."organization_id"::text from "public"."tasks" s where s."id" = (record_consent.subject_id)::uuid)
      else null::text
    end))::uuid;
  if v_tenant is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
      or (coalesce(better_supabase.can('tenant', v_tenant, 'consents.record'), false) and coalesce("better_supabase"."can_subject"(record_consent.subject_type, record_consent.subject_id, 'read'), false))
      or ((v_tenant)::text, (record_consent.subject_type)::text, (record_consent.subject_id)::text) in (select g.tenant, g.party_type, g.party_id from better_supabase.portal_parties() g)
      or exists (select 1 from "better_supabase"."relations" r
      where r."kind" = 'represents' and r."source_type" = 'person'
        and r."tenant_id"::text = (v_tenant)::text
        and r."target_type" = record_consent.subject_type and r."target_id" = (record_consent.subject_id)::text
        and r."data" ->> 'authority' = 'act'
        and (case when r."data" ->> 'valid_from' is null then true
      when pg_input_is_valid(r."data" ->> 'valid_from', 'date') then (r."data" ->> 'valid_from')::date <= current_date
      else false end) and (case when r."data" ->> 'valid_until' is null then true
      when pg_input_is_valid(r."data" ->> 'valid_until', 'date') then (r."data" ->> 'valid_until')::date >= current_date
      else false end)
        and ((v_tenant)::text, ('person')::text, (r."source_id")::text) in (select g.tenant, g.party_type, g.party_id from better_supabase.portal_parties() g))) then
    raise exception 'not allowed to record consent for this record' using errcode = '42501', hint = 'CONSENT_FORBIDDEN';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_tenant, 'consents.record'), false) and coalesce("better_supabase"."can_subject"(record_consent.subject_type, record_consent.subject_id, 'read'), false))) then
    v_representative := (select r."source_id"::uuid from "better_supabase"."relations" r
      where r."kind" = 'represents' and r."source_type" = 'person'
        and r."tenant_id"::text = (v_tenant)::text
        and r."target_type" = record_consent.subject_type and r."target_id" = (record_consent.subject_id)::text
        and r."data" ->> 'authority' = 'act'
        and (case when r."data" ->> 'valid_from' is null then true
      when pg_input_is_valid(r."data" ->> 'valid_from', 'date') then (r."data" ->> 'valid_from')::date <= current_date
      else false end) and (case when r."data" ->> 'valid_until' is null then true
      when pg_input_is_valid(r."data" ->> 'valid_until', 'date') then (r."data" ->> 'valid_until')::date >= current_date
      else false end)
        and ((v_tenant)::text, ('person')::text, (r."source_id")::text) in (select g.tenant, g.party_type, g.party_id from better_supabase.portal_parties() g)
      order by r."source_id" limit 1);
    if v_representative is not null then
      v_given_by := 'representative';
      v_contact := v_representative;
    else
      v_given_by := 'self';
      v_contact := null;
    end if;
  end if;
  if record_consent.status is null or record_consent.status not in ('granted', 'refused') then
    raise exception 'status is granted or refused; withdraw_consent withdraws a consent' using errcode = '22023', hint = 'CONSENT_INVALID';
  end if;
  if v_given_by not in ('self', 'representative') then
    raise exception 'given_by is self or representative' using errcode = '22023', hint = 'CONSENT_INVALID';
  end if;
  if v_given_by = 'self' and v_contact is not null then
    raise exception 'only a representative''s consent names a contact' using errcode = '22023', hint = 'CONSENT_INVALID';
  end if;
  if v_given_by = 'representative' then
    if v_contact is null then
      raise exception 'a representative''s consent names the contact who gave it' using errcode = '22023', hint = 'CONSENT_INVALID';
    end if;
    if not exists (select 1 from "better_supabase"."relations" r
      where r."kind" = 'represents' and r."source_type" = 'person'
        and r."tenant_id"::text = (v_tenant)::text
        and r."target_type" = record_consent.subject_type and r."target_id" = (record_consent.subject_id)::text
        and r."data" ->> 'authority' = 'act'
        and (case when r."data" ->> 'valid_from' is null then true
      when pg_input_is_valid(r."data" ->> 'valid_from', 'date') then (r."data" ->> 'valid_from')::date <= current_date
      else false end) and (case when r."data" ->> 'valid_until' is null then true
      when pg_input_is_valid(r."data" ->> 'valid_until', 'date') then (r."data" ->> 'valid_until')::date >= current_date
      else false end)
        and r."source_id" = (v_contact)::text) then
      raise exception 'the contact doesn''t represent this record with authority to act' using errcode = '22023', hint = 'CONSENT_INVALID';
    end if;
  end if;
  if jsonb_typeof(v_scope) <> 'object' or jsonb_typeof(v_evidence) <> 'object' then
    raise exception 'scope and evidence are JSON objects' using errcode = '22023', hint = 'CONSENT_INVALID';
  end if;
  select * into v_purpose from "better_supabase"."consent_purposes" x
  where x."key" = record_consent.purpose_key
    and (x."tenant_id" = v_tenant or x."tenant_id" is null)
    and x."archived_at" is null
  order by (x."tenant_id" is null), x."created_at" desc, x."id"
  limit 1;
  if not found then
    if exists (
      select 1 from "better_supabase"."consent_purposes" x
      where x."key" = record_consent.purpose_key and (x."tenant_id" = v_tenant or x."tenant_id" is null)
    ) then
      raise exception 'the consent purpose is archived' using errcode = '22023', hint = 'CONSENT_PURPOSE_ARCHIVED';
    end if;
    raise exception 'no such consent purpose' using errcode = 'P0002', hint = 'CONSENT_PURPOSE_NOT_FOUND';
  end if;
  if v_evidence ? 'signatureId' and not pg_input_is_valid(v_evidence ->> 'signatureId', 'uuid') then
    raise exception 'evidence.signatureId is not a uuid' using errcode = '22023', hint = 'CONSENT_INVALID';
  end if;
  v_signature := (v_evidence ->> 'signatureId')::uuid;
  if v_signature is not null and not exists (
    select 1 from "better_supabase"."signatures" x
    where x."id" = v_signature and x."tenant_id"::text = v_tenant::text
  ) then
    raise exception 'evidence.signatureId is not a signature of this organization' using errcode = '22023', hint = 'CONSENT_INVALID';
  end if;
  if v_evidence ? 'submissionId' and not pg_input_is_valid(v_evidence ->> 'submissionId', 'uuid') then
    raise exception 'evidence.submissionId is not a uuid' using errcode = '22023', hint = 'CONSENT_INVALID';
  end if;
  v_submission := (v_evidence ->> 'submissionId')::uuid;
  if v_submission is not null and not exists (
    select 1 from "better_supabase"."form_submissions" x
    where x."id" = v_submission and x."tenant_id"::text = v_tenant::text
  ) then
    raise exception 'evidence.submissionId is not a form submission of this organization' using errcode = '22023', hint = 'CONSENT_INVALID';
  end if;
  if v_evidence ? 'attachmentId' and not pg_input_is_valid(v_evidence ->> 'attachmentId', 'uuid') then
    raise exception 'evidence.attachmentId is not a uuid' using errcode = '22023', hint = 'CONSENT_INVALID';
  end if;
  v_attachment := (v_evidence ->> 'attachmentId')::uuid;
  if v_attachment is not null and not exists (
    select 1 from "better_supabase"."attachments" x
    where x."id" = v_attachment and x."organization_id"::text = v_tenant::text
  ) then
    raise exception 'evidence.attachmentId is not an attachment of this organization' using errcode = '22023', hint = 'CONSENT_INVALID';
  end if;
  if record_consent.status = 'granted' and v_purpose."requires_signature" and v_signature is null then
    raise exception 'this purpose needs a signature to grant consent' using errcode = '22023', hint = 'CONSENT_SIGNATURE_REQUIRED';
  end if;
  if record_consent.status = 'refused' then
    v_until := null;
  elsif v_until is null and v_purpose."valid_months" is not null then
    v_until := now() + make_interval(months => v_purpose."valid_months");
  end if;
  if v_until is not null and v_until <= now() then
    raise exception 'expires_at is in the past' using errcode = '22023', hint = 'CONSENT_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_consent_record"(uuid, text, text, uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::uuid, $5::text)', v_hook::oid::regproc)
        using v_tenant, record_consent.subject_type, record_consent.subject_id, v_purpose."id", record_consent.status;
    end if;
  end;
  update "better_supabase"."consents" x set
    "status" = 'withdrawn',
    "withdrawn_at" = now(), "withdrawn_reason" = 'superseded'
  where x."subject_type" = record_consent.subject_type and x."subject_id" = record_consent.subject_id
    and x."tenant_id" = v_tenant and x."status" = 'granted'
    and x."purpose_id" in (
      select y."id" from "better_supabase"."consent_purposes" y
      where y."key" = v_purpose."key" and (y."tenant_id" = v_tenant or y."tenant_id" is null)
    );
  insert into "better_supabase"."consents" ("tenant_id", "purpose_id", "subject_type", "subject_id", "given_by", "given_by_contact_id", "grantor_id", "status", "scope", "expires_at", "signature_id", "submission_id", "attachment_id", "created_by")
  values (v_tenant, v_purpose."id", record_consent.subject_type, record_consent.subject_id, v_given_by, v_contact, auth.uid(), record_consent.status, v_scope, v_until, v_signature, v_submission, v_attachment, auth.uid())
  returning * into v_row;
  if record_consent.status = 'granted' then
    perform "better_supabase".emit_event('consent.granted', jsonb_build_object('organizationId', v_row."tenant_id", 'consentId', v_row."id", 'purposeId', v_row."purpose_id", 'purposeKey', v_purpose."key", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status", 'givenBy', v_row."given_by"), 'consents/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/consents');
  perform better_supabase.audit_event(
    event_type => 'consent.granted',
    category => 'data',
    target_type => 'consent',
    record_id => v_row."id"::text,
    target_label => v_purpose."title",
    summary => 'recorded a consent',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'consentId', v_row."id", 'purposeId', v_row."purpose_id", 'purposeKey', v_purpose."key", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status", 'givenBy', v_row."given_by")
  );
  else
    perform "better_supabase".emit_event('consent.refused', jsonb_build_object('organizationId', v_row."tenant_id", 'consentId', v_row."id", 'purposeId', v_row."purpose_id", 'purposeKey', v_purpose."key", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status", 'givenBy', v_row."given_by"), 'consents/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/consents');
  perform better_supabase.audit_event(
    event_type => 'consent.refused',
    category => 'data',
    target_type => 'consent',
    record_id => v_row."id"::text,
    target_label => v_purpose."title",
    summary => 'recorded a refused consent',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'consentId', v_row."id", 'purposeId', v_row."purpose_id", 'purposeKey', v_purpose."key", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status", 'givenBy', v_row."given_by")
  );
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_consent_record"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'purposeId', v_row."purpose_id", 'purposeKey', v_purpose."key", 'purposeTitle', v_purpose."title", 'purposeVersion', v_purpose."version", 'legalBasis', v_purpose."legal_basis", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'givenBy', v_row."given_by", 'givenByContactId', v_row."given_by_contact_id", 'givenByUserId', v_row."grantor_id", 'status', v_row."status", 'scope', coalesce(v_row."scope", '{}'::jsonb), 'grantedAt', v_row."granted_at", 'validUntil', v_row."expires_at", 'withdrawnAt', v_row."withdrawn_at", 'withdrawnReason', v_row."withdrawn_reason", 'signatureId', v_row."signature_id", 'submissionId', v_row."submission_id", 'attachmentId', v_row."attachment_id", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'active', (v_row."status" = 'granted' and (v_row."expires_at" is null or v_row."expires_at" > now())));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.referral_attribute (
  tenant         uuid,
  code           text,
  referred_user  uuid DEFAULT NULL::uuid,
  referred_org   uuid DEFAULT NULL::uuid,
  referred_email text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_code "better_supabase"."referral_codes";
  v_ref "better_supabase"."referrals";
begin
  if referral_attribute.referred_user is null and referral_attribute.referred_org is null and nullif(trim(referral_attribute.referred_email), '') is null then
    raise exception 'name the referred user, organization or email' using errcode = '22023', hint = 'REFERRAL_INVALID';
  end if;
  select * into v_ref from "better_supabase"."referrals" x
  where x."tenant_id" = referral_attribute.tenant
    and ((referral_attribute.referred_user is not null and x."referred_id" = referral_attribute.referred_user)
      or (referral_attribute.referred_org is not null and x."referred_organization_id" = referral_attribute.referred_org));
  if found then
    return jsonb_build_object('id', v_ref."id", 'organizationId', v_ref."tenant_id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_id", 'referredOrganizationId', v_ref."referred_organization_id", 'referredEmail', v_ref."referred_email", 'status', v_ref."status", 'rewardAmount', v_ref."reward_amount"::text, 'rewardUnit', v_ref."reward_unit", 'qualifiedAt', v_ref."qualified_at", 'rewardedAt', v_ref."rewarded_at", 'ledgerTransactionId', v_ref."ledger_transaction_id", 'createdAt', v_ref."created_at");
  end if;
  select * into v_code from "better_supabase"."referral_codes" x
  where x."tenant_id" = referral_attribute.tenant and x."code" = upper(trim(referral_attribute.code)) for update;
  if not found or not v_code."active" or (v_code."expires_at" is not null and v_code."expires_at" < now())
    or (v_code."max_uses" is not null and v_code."uses" >= v_code."max_uses") then
    raise exception 'the referral code is unknown, expired or used up' using errcode = 'P0002', hint = 'REFERRAL_CODE_INVALID';
  end if;
  if referral_attribute.referred_user = v_code."referrer_id" then
    raise exception 'a member can''t refer themselves' using errcode = '22023', hint = 'REFERRAL_SELF';
  end if;
  insert into "better_supabase"."referrals" ("tenant_id", "code_id", "referrer_id", "referred_id", "referred_organization_id", "referred_email", "reward_amount", "reward_unit")
  values (referral_attribute.tenant, v_code."id", v_code."referrer_id", referral_attribute.referred_user, referral_attribute.referred_org,
    lower(nullif(trim(referral_attribute.referred_email), '')), v_code."reward_amount", v_code."reward_unit")
  returning * into v_ref;
  update "better_supabase"."referral_codes" x set "uses" = x."uses" + 1 where x."id" = v_code."id";
  perform "better_supabase".emit_event('referral.attributed', jsonb_build_object('organizationId', v_ref."tenant_id", 'id', v_ref."id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_id", 'referredOrganizationId', v_ref."referred_organization_id", 'status', v_ref."status"), 'referrals/' || v_ref."id"::text, (v_ref."tenant_id")::text, null, 'better-supabase/referrals');
  perform better_supabase.audit_event(
    event_type => 'referral.attributed',
    category => 'data',
    target_type => 'referral',
    record_id => v_ref."id"::text,
    summary => 'referral attributed',
    tenant => (v_ref."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_ref."tenant_id", 'id', v_ref."id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_id", 'referredOrganizationId', v_ref."referred_organization_id", 'status', v_ref."status")
  );
  return jsonb_build_object('id', v_ref."id", 'organizationId', v_ref."tenant_id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_id", 'referredOrganizationId', v_ref."referred_organization_id", 'referredEmail', v_ref."referred_email", 'status', v_ref."status", 'rewardAmount', v_ref."reward_amount"::text, 'rewardUnit', v_ref."reward_unit", 'qualifiedAt', v_ref."qualified_at", 'rewardedAt', v_ref."rewarded_at", 'ledgerTransactionId', v_ref."ledger_transaction_id", 'createdAt', v_ref."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.refund_pass_credit()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_spent record;
  v_entry uuid;
begin
  if new."status" <> 'cancelled' or old."status" = 'cancelled'
    or new."cancel_reason" is not distinct from 'bs:moving'
    or now() > lower(new."during") - '12 hours'::interval then
    return null;
  end if;
  for v_spent in
    select r."tenant_id" as tenant, (r."metadata" ->> 'passId')::uuid as pass, x."holder_id" as holder
    from "better_supabase"."ledger_transactions" r
    join "better_supabase"."passes" x on x."id" = (r."metadata" ->> 'passId')::uuid
    where r."tenant_id" = new."tenant_id" and r."idempotency_key" = 'pass-credit:' || new."id"::text || ':booking'
      and not exists (select 1 from "better_supabase"."ledger_transactions" d where d."tenant_id" = r."tenant_id" and d."idempotency_key" = 'pass-credit:' || new."id"::text || ':refund')
  loop
    v_entry := "better_supabase"."ledger_post"(v_spent.tenant, 'pass.credit_refunded',
      jsonb_build_array(
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_spent.tenant, 'pass_credits', 'pass:' || v_spent.pass::text, 'Pass credits', 'credit', 0::smallint,
    'passes', v_spent.pass::text, v_spent.holder, true, 'passes.read', 'passes', jsonb_build_object('passId', v_spent.pass)), 'amount', 1),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_spent.tenant, 'pass_credits_pool', 'pass-credits:pool', 'Pass credits pool', 'credit', 0::smallint,
    null, null, null, true, 'passes.read', 'passes', null), 'amount', -1)),
      'bookings', new."id"::text, null, 'pass-credit:' || new."id"::text || ':refund', clock_timestamp(),
      jsonb_build_object('passId', v_spent.pass, 'reason', 'refund'));
    update "better_supabase"."passes" x set "uses" = greatest(x."uses" - 1, 0), "updated_at" = now()
    where x."id" = v_spent.pass;
    perform "better_supabase".emit_event('pass.credit_refunded', jsonb_build_object('organizationId', v_spent.tenant::text, 'id', v_spent.pass, 'entryId', v_entry, 'bookingId', new."id"), 'passes/' || v_spent.pass::text, (v_spent.tenant)::text, null, 'better-supabase/passes');
  perform better_supabase.audit_event(
    event_type => 'pass.credit_refunded',
    category => 'access',
    target_type => 'pass',
    record_id => v_spent.pass::text,
    summary => 'refunded a credit to pass',
    tenant => (v_spent.tenant)::uuid,
    metadata => jsonb_build_object('organizationId', v_spent.tenant::text, 'id', v_spent.pass, 'entryId', v_entry, 'bookingId', new."id")
  );
  end loop;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.remove_ai_chat_party (
  chat       uuid,
  party_kind text,
  party      text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_chat record;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."id" as id, x."owner_id" as owner, x."organization_id" as tenant into v_chat
  from "better_supabase"."ai_chats" x where x."id" = remove_ai_chat_party.chat for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_chat.owner = (select auth.uid()), false)) then
    raise exception 'No chat %', remove_ai_chat_party.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  delete from "better_supabase"."ai_chat_participants" x
  where x."chat_id" = v_chat.id and x."kind"::text = remove_ai_chat_party.party_kind
    and ((remove_ai_chat_party.party_kind = 'team' and x."team_id" = remove_ai_chat_party.party::uuid) or (remove_ai_chat_party.party_kind = 'customer' and x."customer_id" = remove_ai_chat_party.party::uuid) or (remove_ai_chat_party.party_kind = 'external' and lower(x."email") = lower(btrim(remove_ai_chat_party.party))));
  get diagnostics v_count = row_count;
  if v_count > 0 then
    perform "better_supabase"."ai_chat_notify"(v_chat.id, v_chat.owner, 'participant.removed', jsonb_build_object('kind', remove_ai_chat_party.party_kind), true);
  end if;
  return v_count > 0;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.reopen_deal (
  deal  uuid,
  stage uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."deals";
  v_stage uuid := reopen_deal.stage;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."deals" x where x."id" = reopen_deal.deal and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.write'), false) and (true or coalesce(x."owner_id" = auth.uid(), false)
      or coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.manage'), false)
      or exists (select 1 from "better_supabase"."deal_members" mm where mm."deal_id" = x."id" and mm."user_id" = auth.uid()))));
  if v_row."id" is null then
    raise exception 'no such deal you can edit' using errcode = 'P0002', hint = 'DEAL_NOT_FOUND';
  end if;
  if v_stage is null then
    select st."id" into v_stage from "better_supabase"."pipeline_stages" st
    where st."pipeline_id" = v_row."pipeline_id" and st."archived_at" is null and st."outcome" = 'open'
    order by st."rank" collate "C" limit 1;
  end if;
  update "better_supabase"."deals" x set "stage_id" = v_stage where x."id" = reopen_deal.deal;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text, 'amount', x."amount"::text, 'existing_amount', x."existing_amount"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text) || jsonb_build_object(
      'contacts', coalesce((select jsonb_agg(jsonb_build_object('type', ck."contact_type", 'id', ck."contact_id", 'role', ck."role", 'primary', ck."is_primary") order by ck."is_primary" desc, ck."contact_id") from "better_supabase"."deal_contacts" ck where ck."deal_id" = x."id"), '[]'::jsonb),
      'members', coalesce((select jsonb_agg(jsonb_build_object('userId', cm."user_id", 'role', cm."role") order by cm."user_id") from "better_supabase"."deal_members" cm where cm."deal_id" = x."id"), '[]'::jsonb)) from "better_supabase"."deals" x where x."id" = reopen_deal.deal);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.request_ai_chat_stop (
  chat uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_chat "better_supabase"."ai_chats";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_chat from "better_supabase"."ai_chats" x where x."id" = request_ai_chat_stop.chat for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_chat."owner_id" = (select auth.uid()), false) or (v_chat."visibility" <> 'private' and exists (select 1 from "better_supabase"."ai_chat_participants" pa where pa."chat_id" = v_chat."id" and pa."role"::text in ('editor') and ((((pa."kind"::text = 'user' and pa."user_id" = (select auth.uid())) or (pa."kind"::text = 'team' and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = pa."team_id"::text and tm."user_id" = (select auth.uid())))) and (v_chat."organization_id" is null or v_chat."organization_id" in (select better_supabase.member_organization_ids()))) or (pa."kind"::text = 'customer' and pa."customer_id" = (select auth.uid()) and ((v_chat."organization_id")::text, ('ai-chat')::text, (v_chat."id"::text)::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g)))))) then
    raise exception 'No chat %', request_ai_chat_stop.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  if v_chat."active_stream_id" is null then
    return null;
  end if;
  update "better_supabase"."ai_runs" x set "status" = 'cancel_requested'
  where x."id" = v_chat."active_run_id" and x."status" in ('queued', 'running');
  perform "better_supabase"."stream_cancel"(v_chat."active_stream_id");
  perform "better_supabase"."ai_chat_notify"(v_chat."id", null, 'stream.stopping', jsonb_build_object('streamId', v_chat."active_stream_id"), false);
  return jsonb_build_object('stream_id', v_chat."active_stream_id", 'run_id', v_chat."active_run_id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.request_shift_swap (
  assignment_id uuid,
  to_id         uuid,
  note          text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_shift "better_supabase"."shifts"%rowtype;
  v_row "better_supabase"."shift_assignments"%rowtype;
  v_swap "better_supabase"."shift_swaps"%rowtype;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."shift_assignments" x where x."id" = request_shift_swap.assignment_id;
  if not found then
    raise exception 'shift assignment not found' using errcode = 'P0002', hint = 'SHIFT_ASSIGNMENT_NOT_FOUND';
  end if;
  if not (v_row."user_id" = (select auth.uid()) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'shifts.write'), false))) then
    raise exception 'not allowed to swap this shift' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  select * into v_shift from "better_supabase"."shifts" x where x."id" = v_row."shift_id";
  if v_row."status" <> 'assigned' or v_shift."status" = 'canceled' or v_shift."starts_at" <= now() then
    raise exception 'only an assigned shift that hasn''t started can be swapped' using errcode = '22023', hint = 'SHIFT_SWAP_INVALID';
  end if;
  if request_shift_swap.to_id is null or request_shift_swap.to_id = v_row."user_id" or not exists (select 1 from "public"."memberships" mm where mm."organization_id" = v_row."tenant_id" and mm."user_id" = request_shift_swap.to_id) then
    raise exception 'the swap goes to another member of this organization' using errcode = '22023', hint = 'SHIFT_SWAP_INVALID';
  end if;
  if request_shift_swap.note is not null and length(request_shift_swap.note) > 2000 then
    raise exception 'a note is at most 2000 characters' using errcode = '22023', hint = 'SHIFT_SWAP_INVALID';
  end if;
  if exists (select 1 from "better_supabase"."shift_swaps" x where x."assignment_id" = v_row."id" and x."status" = 'pending') then
    raise exception 'the shift already has a pending swap' using errcode = '22023', hint = 'SHIFT_SWAP_INVALID';
  end if;
  insert into "better_supabase"."shift_swaps" ("tenant_id", "assignment_id", "from_id", "to_id", "note")
  values (v_row."tenant_id", v_row."id", v_row."user_id", request_shift_swap.to_id, nullif(trim(request_shift_swap.note), ''))
  returning * into v_swap;
  perform "better_supabase".emit_event('shift_swap.requested', jsonb_build_object('organizationId', v_swap."tenant_id", 'swapId', v_swap."id", 'assignmentId', v_swap."assignment_id", 'shiftId', v_shift."id", 'fromUserId', v_swap."from_id", 'toUserId', v_swap."to_id"), 'shifts/' || v_shift."id"::text, (v_swap."tenant_id")::text, null, 'better-supabase/shifts');
  perform better_supabase.audit_event(
    event_type => 'shift_swap.requested',
    category => 'data',
    target_type => 'shift_swap',
    record_id => v_swap."id"::text,
    summary => 'Shift swap requested',
    tenant => (v_swap."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_swap."tenant_id", 'swapId', v_swap."id", 'assignmentId', v_swap."assignment_id", 'shiftId', v_shift."id", 'fromUserId', v_swap."from_id", 'toUserId', v_swap."to_id")
  );
  if better_supabase.import_run() is null then
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'shift_swap.requested',
      'tenant', v_shift."tenant_id",
      'actor', (select auth.uid()),
      'subject_type', 'shift',
      'subject_id', v_shift."id"::text,
      'summary', 'A shift swap is offered to you',
      'recipients', jsonb_build_array(v_swap."to_id"),
      'key', 'shift_swap.requested:' || v_shift."id"::text || ':' || v_swap."to_id"::text,
      'data', jsonb_build_object('startsAt', v_shift."starts_at", 'endsAt', v_shift."ends_at")
    ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  return jsonb_build_object('id', v_swap."id", 'organizationId', v_swap."tenant_id", 'assignmentId', v_swap."assignment_id", 'fromUserId', v_swap."from_id", 'toUserId', v_swap."to_id", 'status', v_swap."status", 'approvalId', v_swap."approval_id", 'note', v_swap."note", 'decidedBy', v_swap."decided_by", 'decidedAt', v_swap."decided_at", 'createdAt', v_swap."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.reschedule_booking (
  booking   uuid,
  starts_at timestamp with time zone,
  scope     text                     DEFAULT 'one'::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_booking "better_supabase"."bookings"%rowtype;
  v_shift interval;
  v_id uuid;
  v_moved jsonb := '[]'::jsonb;
begin
  select * into v_booking from "better_supabase"."bookings" bk where bk."id" = reschedule_booking.booking;
  if not found or not ((auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_booking."tenant_id", 'bookings.manage'), false)) or (coalesce(v_booking."customer_id" = auth.uid(), false) and (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_booking."tenant_id", 'bookings.create'), false)))) then
    raise exception 'booking not found' using errcode = 'P0002', hint = 'BOOKING_NOT_FOUND';
  end if;
  if reschedule_booking.scope is null or reschedule_booking.scope not in ('one', 'following') then
    raise exception 'scope is one or following' using errcode = '22023', hint = 'BOOKING_SCOPE_INVALID';
  end if;
  if reschedule_booking.scope = 'one' or v_booking."series_id" is null then
    return jsonb_build_array("better_supabase"."move_booking"(v_booking."id", reschedule_booking.starts_at));
  end if;
  v_shift := reschedule_booking.starts_at - lower(v_booking."during");
  -- Later occurrences move first when the shift is positive, so a series never
  -- collides with itself.
  for v_id in
    select bk."id" from "better_supabase"."bookings" bk
    where bk."series_id" = v_booking."series_id" and bk."status" <> 'cancelled'
      and lower(bk."during") >= lower(v_booking."during")
    order by case when v_shift > interval '0' then lower(bk."during") end desc, lower(bk."during")
  loop
    v_moved := v_moved || jsonb_build_array("better_supabase"."move_booking"(v_id, (select lower(x."during") from "better_supabase"."bookings" x where x."id" = v_id) + v_shift));
  end loop;
  return (select jsonb_agg(m order by (m ->> 'startsAt')::timestamptz) from jsonb_array_elements(v_moved) m);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.respond_to_portal_quote (
  quote    uuid,
  decision text,
  name     text,
  note     text,
  selected jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."quotes";
  v_headers jsonb := nullif(current_setting('request.headers', true), '')::jsonb;
  v_ip inet;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = respond_to_portal_quote.quote and (x."status" <> 'draft' and (((x."tenant_id")::text, ('quote')::text, (x."id"::text)::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g) or ((x."tenant_id")::text, (x."company_type")::text, (x."company_id")::text) in (select g.tenant, g.party_type, g.party_id from better_supabase.portal_parties() g) or ((x."tenant_id")::text, (x."contact_type")::text, (x."contact_id")::text) in (select g.tenant, g.party_type, g.party_id from better_supabase.portal_parties() g))) for update;
  if v_row."id" is null then
    raise exception 'no such quote shared with you' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if respond_to_portal_quote.decision not in ('accepted', 'rejected', 'changes_requested') then
    raise exception 'answer accepted, rejected or changes_requested' using errcode = '22023', hint = 'QUOTE_DECISION_INVALID';
  end if;
  if v_row."status" not in ('sent', 'viewed') then
    raise exception 'this quote no longer takes an answer' using errcode = '55000', hint = 'QUOTE_NOT_OPEN';
  end if;
  begin
    v_ip := left(nullif(trim(reverse(split_part(reverse(v_headers ->> 'x-forwarded-for'), ',', 1))), ''), 64)::inet;
  exception when invalid_text_representation then
    v_ip := null;
  end;
  perform set_config('better_supabase.transition_actor', jsonb_strip_nulls(jsonb_build_object('name', nullif(trim(coalesce(nullif(trim(respond_to_portal_quote.name), ''), auth.jwt() ->> 'email')), ''), 'email', auth.jwt() ->> 'email', 'ip', v_ip::text, 'userAgent', left(v_headers ->> 'user-agent', 512)))::text, true);
  if (true) and v_row."valid_until" < current_date then
    update "better_supabase"."quotes" x set "status" = 'expired', "updated_at" = now() where x."id" = v_row."id"
    returning * into v_row;
    perform "better_supabase".emit_event('quote.expired', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier"), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
    return jsonb_build_object('status', 'expired');
  end if;
  if nullif(trim(coalesce(nullif(trim(respond_to_portal_quote.name), ''), auth.jwt() ->> 'email')), '') is null then
    raise exception 'say who answers' using errcode = '23502', hint = 'QUOTE_NAME_REQUIRED';
  end if;
  if respond_to_portal_quote.decision = 'accepted' then
    if v_row."deposit_required" and v_row."deposit_due" > 0 then
      raise exception 'pay the deposit before accepting; the app records the acceptance once it is paid' using errcode = '55000', hint = 'QUOTE_DEPOSIT_REQUIRED';
    end if;
    if respond_to_portal_quote.selected is not null then
      if jsonb_typeof(respond_to_portal_quote.selected) <> 'array' or exists (
        select 1 from jsonb_array_elements(respond_to_portal_quote.selected) e
        where jsonb_typeof(e.value) not in ('number') or not exists (
          select 1 from "better_supabase"."quote_lines" ql
          where ql."parent_id" = v_row."id" and ql."optional" and ql."position" = (e.value #>> '{}')::numeric
        )
      ) then
        raise exception 'pick optional lines of this quote by position' using errcode = '22023', hint = 'QUOTE_SELECTION_INVALID';
      end if;
      update "better_supabase"."quote_lines" ql set "selected" = ql."position" in (select ((e.value #>> '{}')::numeric)::integer from jsonb_array_elements(respond_to_portal_quote.selected) e)
      where ql."parent_id" = v_row."id" and ql."optional";
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_quote_accept"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  update "better_supabase"."quotes" x set "status" = respond_to_portal_quote.decision, "decided_at" = now(), "decided_by" = nullif(trim(coalesce(nullif(trim(respond_to_portal_quote.name), ''), auth.jwt() ->> 'email')), ''),
    "decision_note" = nullif(trim(respond_to_portal_quote.note), ''), "decider_id" = auth.uid(), "decided_ip" = left(nullif(trim(reverse(split_part(reverse(v_headers ->> 'x-forwarded-for'), ',', 1))), ''), 64), "decided_user_agent" = left(v_headers ->> 'user-agent', 512), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  case respond_to_portal_quote.decision
    when 'accepted' then
      perform "better_supabase".emit_event('quote.accepted', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'total', v_row."total"::text, 'currency', v_row."currency", 'byName', v_row."decided_by", 'revision', v_row."revision", 'depositDue', v_row."deposit_due"::text), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
    when 'rejected' then
      perform "better_supabase".emit_event('quote.rejected', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'note', v_row."decision_note"), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
    else
      perform "better_supabase".emit_event('quote.changes_requested', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'note', v_row."decision_note"), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
  end case;
  if v_row."owner_id" is not null then
    if better_supabase.import_run() is null then
      v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'quote.decided',
      'tenant', v_row."tenant_id",
      'subject_type', 'quote',
      'subject_id', v_row."id"::text,
      'subject_label', v_row."identifier" || ' ' || v_row."title",
      'summary', v_row."identifier" || ' ' || v_row."title",
      'recipients', jsonb_build_array(v_row."owner_id"),
      'key', 'quote.decided:' || v_row."id"::text,
      'data', jsonb_build_object('quoteId', v_row."id", 'status', v_row."status")
    ));
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
  end if;
  if respond_to_portal_quote.decision = 'accepted' then
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_quote_accept"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  return jsonb_build_object('status', v_row."status", 'identifier', v_row."identifier", 'revision', v_row."revision");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.respond_to_quote (
  token    text,
  decision text,
  name     text,
  note     text,
  selected jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."quotes";
  v_headers jsonb := nullif(current_setting('request.headers', true), '')::jsonb;
  v_ip inet;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."token_hash" = encode(extensions.digest(respond_to_quote.token, 'sha256'), 'hex') for update;
  if v_row."id" is null then
    raise exception 'this link is not valid' using errcode = 'P0002', hint = 'QUOTE_LINK_INVALID';
  end if;
  if respond_to_quote.decision not in ('accepted', 'rejected', 'changes_requested') then
    raise exception 'answer accepted, rejected or changes_requested' using errcode = '22023', hint = 'QUOTE_DECISION_INVALID';
  end if;
  if v_row."status" not in ('sent', 'viewed') then
    raise exception 'this quote no longer takes an answer' using errcode = '55000', hint = 'QUOTE_NOT_OPEN';
  end if;
  begin
    v_ip := left(nullif(trim(reverse(split_part(reverse(v_headers ->> 'x-forwarded-for'), ',', 1))), ''), 64)::inet;
  exception when invalid_text_representation then
    v_ip := null;
  end;
  perform set_config('better_supabase.transition_actor', jsonb_strip_nulls(jsonb_build_object('name', nullif(trim(respond_to_quote.name), ''), 'email', auth.jwt() ->> 'email', 'ip', v_ip::text, 'userAgent', left(v_headers ->> 'user-agent', 512)))::text, true);
  if (true) and v_row."valid_until" < current_date then
    update "better_supabase"."quotes" x set "status" = 'expired', "updated_at" = now() where x."id" = v_row."id"
    returning * into v_row;
    perform "better_supabase".emit_event('quote.expired', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier"), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
    return jsonb_build_object('status', 'expired');
  end if;
  if nullif(trim(respond_to_quote.name), '') is null then
    raise exception 'say who answers' using errcode = '23502', hint = 'QUOTE_NAME_REQUIRED';
  end if;
  if respond_to_quote.decision = 'accepted' then
    if v_row."deposit_required" and v_row."deposit_due" > 0 then
      raise exception 'pay the deposit before accepting; the app records the acceptance once it is paid' using errcode = '55000', hint = 'QUOTE_DEPOSIT_REQUIRED';
    end if;
    if respond_to_quote.selected is not null then
      if jsonb_typeof(respond_to_quote.selected) <> 'array' or exists (
        select 1 from jsonb_array_elements(respond_to_quote.selected) e
        where jsonb_typeof(e.value) not in ('number') or not exists (
          select 1 from "better_supabase"."quote_lines" ql
          where ql."parent_id" = v_row."id" and ql."optional" and ql."position" = (e.value #>> '{}')::numeric
        )
      ) then
        raise exception 'pick optional lines of this quote by position' using errcode = '22023', hint = 'QUOTE_SELECTION_INVALID';
      end if;
      update "better_supabase"."quote_lines" ql set "selected" = ql."position" in (select ((e.value #>> '{}')::numeric)::integer from jsonb_array_elements(respond_to_quote.selected) e)
      where ql."parent_id" = v_row."id" and ql."optional";
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_quote_accept"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  update "better_supabase"."quotes" x set "status" = respond_to_quote.decision, "decided_at" = now(), "decided_by" = nullif(trim(respond_to_quote.name), ''),
    "decision_note" = nullif(trim(respond_to_quote.note), ''), "decider_id" = auth.uid(), "decided_ip" = left(nullif(trim(reverse(split_part(reverse(v_headers ->> 'x-forwarded-for'), ',', 1))), ''), 64), "decided_user_agent" = left(v_headers ->> 'user-agent', 512), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  case respond_to_quote.decision
    when 'accepted' then
      perform "better_supabase".emit_event('quote.accepted', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'total', v_row."total"::text, 'currency', v_row."currency", 'byName', v_row."decided_by", 'revision', v_row."revision", 'depositDue', v_row."deposit_due"::text), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
    when 'rejected' then
      perform "better_supabase".emit_event('quote.rejected', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'note', v_row."decision_note"), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
    else
      perform "better_supabase".emit_event('quote.changes_requested', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'note', v_row."decision_note"), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
  end case;
  if v_row."owner_id" is not null then
    if better_supabase.import_run() is null then
      v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'quote.decided',
      'tenant', v_row."tenant_id",
      'subject_type', 'quote',
      'subject_id', v_row."id"::text,
      'subject_label', v_row."identifier" || ' ' || v_row."title",
      'summary', v_row."identifier" || ' ' || v_row."title",
      'recipients', jsonb_build_array(v_row."owner_id"),
      'key', 'quote.decided:' || v_row."id"::text,
      'data', jsonb_build_object('quoteId', v_row."id", 'status', v_row."status")
    ));
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
  end if;
  if respond_to_quote.decision = 'accepted' then
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_quote_accept"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  return jsonb_build_object('status', v_row."status", 'identifier', v_row."identifier", 'revision', v_row."revision");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.revise_quote (
  quote uuid,
  actor jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."quotes";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = revise_quote.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false)) for update;
  if v_row."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if v_row."status" = 'draft' then
    raise exception 'a draft is edited, not revised' using errcode = '55000', hint = 'QUOTE_NOT_SENT';
  end if;
  if v_row."status" = 'accepted' then
    raise exception 'an accepted quote stays as accepted; start a new quote' using errcode = '55000', hint = 'QUOTE_ACCEPTED';
  end if;
  if revise_quote.actor is not null then
    if jsonb_typeof(revise_quote.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(revise_quote.actor ->> 'ip', '')::inet, nullif(revise_quote.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(revise_quote.actor::text, ''), true);
  update "better_supabase"."quotes" x set "status" = 'draft', "revision" = x."revision" + 1, "token_hash" = null, "sent_at" = null, "viewed_at" = null,
    "valid_until" = greatest(x."valid_until", current_date + 30),
    "decided_at" = null, "decided_by" = null, "decision_note" = null, "decider_id" = null, "decided_ip" = null, "decided_user_agent" = null, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('quote.revised', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'revision', v_row."revision"), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
  return (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'unit', ql."unit", 'discountKind', ql."discount_kind", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
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
    perform "better_supabase".emit_event('pass.revoked', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id"), 'passes/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/passes');
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
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id"::text, 'kind', v_row."kind", 'holderUserId', v_row."holder_id", 'holderName', v_row."holder_name", 'holderEmail', v_row."holder_email", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'bookingId', v_row."booking_id", 'resourceId', v_row."resource_id", 'usesAllowed', v_row."uses_allowed", 'uses', v_row."uses", 'validFrom', v_row."starts_at", 'validUntil', v_row."expires_at", 'status', v_row."status", 'issuedBy', v_row."issued_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'revokedAt', v_row."revoked_at");
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
  v_item jsonb;
  v_task uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."type" into v_tenant, v_type
  from "better_supabase"."activities" x where x."id" = save_activity_notes.engagement and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false));
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
  insert into "better_supabase"."engagement_notes" ("activity_id", "tenant_id", "summary", "model", "source", "created_by")
  values (save_activity_notes.engagement, v_tenant, v_summary, nullif(save_activity_notes.notes ->> 'model', ''), case when save_activity_notes.notes ->> 'source' = 'member' then 'member' else 'ai' end, auth.uid())
  on conflict ("activity_id") do update set
    "summary" = excluded."summary",
    "model" = excluded."model", "source" = excluded."source", "updated_at" = now();
  for v_item in select i.value from jsonb_array_elements(v_items) i loop
    if not exists (
      select 1 from "better_supabase"."activity_note_actions" ax join "better_supabase"."work_items" k on k."id" = ax."task_id"
      where ax."activity_id" = save_activity_notes.engagement and k."title" = left(btrim(v_item ->> 'text'), 500)
    ) then
      v_task := ("better_supabase"."create_work_item"(
        v_tenant,
        jsonb_strip_nulls(jsonb_build_object('title', left(btrim(v_item ->> 'text'), 500), 'dueAt', v_item ->> 'dueAt')),
        case when nullif(v_item ->> 'ownerId', '') is null then '{}'::uuid[] else array[(v_item ->> 'ownerId')::uuid] end
      ) ->> 'id')::uuid;
      insert into "better_supabase"."activity_note_actions" ("tenant_id", "activity_id", "task_id")
      values (v_tenant, save_activity_notes.engagement, v_task);
    end if;
  end loop;
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = save_activity_notes.engagement), '[]'::jsonb);
  v_first := v_subjects -> 0;
  perform "better_supabase".emit_event('activity.summarized', jsonb_build_object('organizationId', v_tenant, 'engagementId', save_activity_notes.engagement, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects), 'engagements/' || save_activity_notes.engagement::text, (v_tenant::text)::text, 'activity.summarized:' || save_activity_notes.engagement::text || ':' || md5(save_activity_notes.notes::text), 'better-supabase/activities');
  return (select jsonb_build_object('engagementId', nx."activity_id", 'organizationId', nx."tenant_id", 'summary', nx."summary", 'actionTaskIds', coalesce((select jsonb_agg(ax."task_id" order by ax."created_at", ax."id") from "better_supabase"."activity_note_actions" ax where ax."activity_id" = nx."activity_id"), '[]'::jsonb), 'model', nx."model", 'source', nx."source", 'createdBy', nx."created_by", 'createdAt', nx."created_at", 'updatedAt', nx."updated_at") from "better_supabase"."engagement_notes" nx where nx."activity_id" = save_activity_notes.engagement);
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
  select rx."activity_id", rx."tenant_id", x."type" into v_engagement, v_tenant, v_type
  from "better_supabase"."engagement_recordings" rx
  join "better_supabase"."activities" x on x."id" = rx."activity_id"
  where rx."id" = v_recording and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false))
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
  insert into "better_supabase"."engagement_transcript_segments" ("recording_id", "tenant_id", "position", "speaker", "speaker_id", "starts_ms", "ends_ms", "text", "confidence")
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
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = v_engagement), '[]'::jsonb);
  v_first := v_subjects -> 0;
  perform "better_supabase".emit_event('activity.transcribed', jsonb_build_object('organizationId', v_tenant, 'engagementId', v_engagement, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects, 'recordingId', v_recording), 'engagements/' || v_engagement::text, (v_tenant::text)::text, 'activity.transcribed:' || v_recording::text || ':' || md5(save_activity_transcript.segments::text), 'better-supabase/activities');
  return (select jsonb_build_object('id', rx."id", 'organizationId', rx."tenant_id", 'engagementId', rx."activity_id", 'fileId', rx."file_id", 'filename', rx."filename", 'mediaType', rx."media_type", 'status', rx."status", 'language', rx."language", 'durationSeconds', rx."duration_seconds", 'error', rx."error", 'model', rx."model", 'segmentCount', (select count(*)::integer from "better_supabase"."engagement_transcript_segments" sc where sc."recording_id" = rx."id"), 'createdBy', rx."created_by", 'createdAt', rx."created_at", 'transcribedAt', rx."transcribed_at") from "better_supabase"."engagement_recordings" rx where rx."id" = v_recording);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_booking_resource (
  tenant uuid,
  item   jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_item jsonb := coalesce(save_booking_resource.item, '{}'::jsonb);
  v_tenant uuid := save_booking_resource.tenant;
  v_id uuid := nullif(v_item ->> 'id', '')::uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'bookings.manage'), false)) then
    raise exception 'not allowed to manage bookings' using errcode = '42501', hint = 'BOOKING_FORBIDDEN';
  end if;
  if v_item ? 'tz' and not exists (select 1 from pg_catalog.pg_timezone_names z where z.name = v_item ->> 'tz') then
    raise exception 'tz must be an IANA time zone' using errcode = '22023', hint = 'BOOKING_TZ_INVALID';
  end if;
  if v_id is null then
    insert into "better_supabase"."booking_resources" ("tenant_id", "name", "kind", "capacity", "tz", "active", "calendar_id", "host_id", "check_busy")
    values (v_tenant, case when v_item ? 'name' then v_item ->> 'name' else null end, case when v_item ? 'kind' then v_item ->> 'kind' else 'staff' end, case when v_item ? 'capacity' then (v_item ->> 'capacity')::integer else 1 end, case when v_item ? 'tz' then v_item ->> 'tz' else 'UTC' end, case when v_item ? 'active' then (v_item ->> 'active')::boolean else true end, case when v_item ? 'calendarId' then nullif(v_item ->> 'calendarId', '')::uuid else null end, case when v_item ? 'hostUserId' then nullif(v_item ->> 'hostUserId', '')::uuid else null end, case when v_item ? 'checkBusy' then (v_item ->> 'checkBusy')::boolean else false end)
    returning "id" into v_id;
  else
    update "better_supabase"."booking_resources" set "name" = case when v_item ? 'name' then v_item ->> 'name' else "name" end, "kind" = case when v_item ? 'kind' then v_item ->> 'kind' else "kind" end, "capacity" = case when v_item ? 'capacity' then (v_item ->> 'capacity')::integer else "capacity" end, "tz" = case when v_item ? 'tz' then v_item ->> 'tz' else "tz" end, "active" = case when v_item ? 'active' then (v_item ->> 'active')::boolean else "active" end, "calendar_id" = case when v_item ? 'calendarId' then nullif(v_item ->> 'calendarId', '')::uuid else "calendar_id" end, "host_id" = case when v_item ? 'hostUserId' then nullif(v_item ->> 'hostUserId', '')::uuid else "host_id" end, "check_busy" = case when v_item ? 'checkBusy' then (v_item ->> 'checkBusy')::boolean else "check_busy" end
    where "id" = v_id and "tenant_id" = v_tenant;
    if not found then
      raise exception 'not found' using errcode = 'P0002', hint = 'BOOKING_NOT_FOUND';
    end if;
  end if;
  return jsonb_build_object('id', v_id);
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
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_company.tenant, 'contacts.write'), false)) then
    raise exception 'not allowed to change companies and people' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  if jsonb_typeof(coalesce(save_company.attrs, '{}')) <> 'object' then
    raise exception 'attrs must be an object' using errcode = '22023', hint = 'PARTY_ATTRS_INVALID';
  end if;
  if save_company.attrs ? 'lifecycle' and not (save_company.attrs ->> 'lifecycle' = any ('{lead,prospect,customer,churned}'::text[])) then
    raise exception 'unknown lifecycle stage' using errcode = '22023', hint = 'PARTY_LIFECYCLE_INVALID';
  end if;
  if save_company.attrs ->> 'customerTermsId' is not null and not exists (select 1 from "better_supabase"."payment_terms" pt where pt."id"::text = save_company.attrs ->> 'customerTermsId' and pt."tenant_id" = save_company.tenant) then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_company.attrs ->> 'supplierTermsId' is not null and not exists (select 1 from "better_supabase"."payment_terms" pt where pt."id"::text = save_company.attrs ->> 'supplierTermsId' and pt."tenant_id" = save_company.tenant) then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_company.attrs ->> 'creditBlock' is not null and lower(trim(save_company.attrs ->> 'creditBlock')) not in ('none', 'soft', 'hard') then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_company.attrs ->> 'language' is not null and nullif(trim(save_company.attrs ->> 'language'), '') is not null and trim(save_company.attrs ->> 'language') !~ '^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$' then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_company.attrs ->> 'creditLimit' is not null and save_company.attrs ->> 'creditLimit' !~ '^[0-9]{1,18}$' then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_company.attrs ->> 'creditCurrency' is not null and upper(trim(save_company.attrs ->> 'creditCurrency')) !~ '^[A-Z]{3}$' then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_company.attrs ? 'creditLimit' <> save_company.attrs ? 'creditCurrency' then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_company.attrs ? 'creditLimit' and (save_company.attrs ->> 'creditLimit' is null) <> (nullif(trim(save_company.attrs ->> 'creditCurrency'), '') is null) then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
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
      insert into "better_supabase"."companies" ("tenant_id", "name", "domain", "website", "vat_id", "legal_name", "registration_id", "phone", "lifecycle", "owner_id", "customer_terms_id", "supplier_terms_id", "credit_limit", "credit_currency", "credit_block", "language", "address", "created_by")
      values (save_company.tenant, nullif(trim(save_company.attrs ->> 'name'), ''), lower(nullif(trim(save_company.attrs ->> 'domain'), '')), nullif(trim(save_company.attrs ->> 'website'), ''), nullif(trim(save_company.attrs ->> 'vatId'), ''), nullif(trim(save_company.attrs ->> 'legalName'), ''), nullif(trim(save_company.attrs ->> 'registrationId'), ''), nullif(trim(save_company.attrs ->> 'phone'), ''), coalesce(nullif(trim(save_company.attrs ->> 'lifecycle'), ''), ('{lead,prospect,customer,churned}'::text[])[1]), nullif(save_company.attrs ->> 'ownerId', '')::uuid, nullif(save_company.attrs ->> 'customerTermsId', '')::uuid, nullif(save_company.attrs ->> 'supplierTermsId', '')::uuid, nullif(trim(save_company.attrs ->> 'creditLimit'), '')::bigint, upper(nullif(trim(save_company.attrs ->> 'creditCurrency'), '')), lower(nullif(trim(save_company.attrs ->> 'creditBlock'), '')), nullif(trim(save_company.attrs ->> 'language'), ''), save_company.attrs -> 'address', auth.uid())
      returning "id", "owner_id" into v_id, v_owner;
    else
      select x."owner_id" into v_previous_owner from "better_supabase"."companies" x
      where x."id" = save_company.company and x."tenant_id" = save_company.tenant;
      update "better_supabase"."companies" x set "name" = case when save_company.attrs ? 'name' then coalesce(nullif(trim(save_company.attrs ->> 'name'), ''), x."name") else x."name" end,
        "domain" = case when save_company.attrs ? 'domain' then lower(nullif(trim(save_company.attrs ->> 'domain'), '')) else x."domain" end,
        "website" = case when save_company.attrs ? 'website' then nullif(trim(save_company.attrs ->> 'website'), '') else x."website" end,
        "vat_id" = case when save_company.attrs ? 'vatId' then nullif(trim(save_company.attrs ->> 'vatId'), '') else x."vat_id" end,
        "legal_name" = case when save_company.attrs ? 'legalName' then nullif(trim(save_company.attrs ->> 'legalName'), '') else x."legal_name" end,
        "registration_id" = case when save_company.attrs ? 'registrationId' then nullif(trim(save_company.attrs ->> 'registrationId'), '') else x."registration_id" end,
        "phone" = case when save_company.attrs ? 'phone' then nullif(trim(save_company.attrs ->> 'phone'), '') else x."phone" end,
        "lifecycle" = case when save_company.attrs ? 'lifecycle' then coalesce(nullif(trim(save_company.attrs ->> 'lifecycle'), ''), x."lifecycle") else x."lifecycle" end,
        "owner_id" = case when save_company.attrs ? 'ownerId' then nullif(save_company.attrs ->> 'ownerId', '')::uuid else x."owner_id" end,
        "customer_terms_id" = case when save_company.attrs ? 'customerTermsId' then nullif(save_company.attrs ->> 'customerTermsId', '')::uuid else x."customer_terms_id" end,
        "supplier_terms_id" = case when save_company.attrs ? 'supplierTermsId' then nullif(save_company.attrs ->> 'supplierTermsId', '')::uuid else x."supplier_terms_id" end,
        "credit_limit" = case when save_company.attrs ? 'creditLimit' then nullif(trim(save_company.attrs ->> 'creditLimit'), '')::bigint else x."credit_limit" end,
        "credit_currency" = case when save_company.attrs ? 'creditCurrency' then upper(nullif(trim(save_company.attrs ->> 'creditCurrency'), '')) else x."credit_currency" end,
        "credit_block" = case when save_company.attrs ? 'creditBlock' then lower(nullif(trim(save_company.attrs ->> 'creditBlock'), '')) else x."credit_block" end,
        "language" = case when save_company.attrs ? 'language' then nullif(trim(save_company.attrs ->> 'language'), '') else x."language" end,
        "address" = case when save_company.attrs ? 'address' then save_company.attrs -> 'address' else x."address" end,
        "updated_at" = now()
      where x."id" = save_company.company and x."tenant_id" = save_company.tenant and x."merged_into" is null
      returning x."owner_id" into v_owner;
      if not found then
        raise exception 'company not found' using errcode = 'P0002', hint = 'PARTY_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'another company has this domain' using errcode = '23505', hint = 'PARTY_DOMAIN_TAKEN';
  end;
  select to_jsonb(x) || jsonb_build_object('roles', x."roles", 'customer_terms_id', x."customer_terms_id", 'supplier_terms_id', x."supplier_terms_id", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'credit_block', x."credit_block", 'supplier_status', x."supplier_status", 'language', x."language") into v_row from "better_supabase"."companies" x where x."id" = v_id;
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

CREATE OR REPLACE FUNCTION better_supabase.save_goal (
  tenant uuid,
  target uuid,
  attrs  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid := save_goal.target;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_goal.tenant, 'goals.manage'), false)) then
    raise exception 'not allowed to manage targets' using errcode = '42501', hint = 'GOAL_FORBIDDEN';
  end if;
  begin
    if v_id is null then
      insert into "better_supabase"."goals" ("tenant_id", "name", "metric", "owner_id", "team_id", "period_start", "period_end", "currency", "goal", "actual")
      values (save_goal.tenant, save_goal.attrs ->> 'name', save_goal.attrs ->> 'metric', (save_goal.attrs ->> 'ownerId')::uuid,
        (save_goal.attrs ->> 'teamId')::uuid, (save_goal.attrs ->> 'periodStart')::date, (save_goal.attrs ->> 'periodEnd')::date,
        upper(save_goal.attrs ->> 'currency'), (save_goal.attrs ->> 'goal')::bigint, coalesce((save_goal.attrs ->> 'actual')::bigint, 0))
      returning "id" into v_id;
    else
      update "better_supabase"."goals" x set
        "name" = coalesce(save_goal.attrs ->> 'name', x."name"),
        "goal" = coalesce((save_goal.attrs ->> 'goal')::bigint, x."goal"),
        "actual" = coalesce((save_goal.attrs ->> 'actual')::bigint, x."actual"),
        "period_start" = coalesce((save_goal.attrs ->> 'periodStart')::date, x."period_start"),
        "period_end" = coalesce((save_goal.attrs ->> 'periodEnd')::date, x."period_end"),
        "archived_at" = case when coalesce((save_goal.attrs ->> 'archived')::boolean, false) then coalesce(x."archived_at", now()) else x."archived_at" end,
        "updated_at" = now()
      where x."id" = v_id and x."tenant_id" = save_goal.tenant;
      if not found then
        raise exception 'target not found' using errcode = 'P0002', hint = 'GOAL_NOT_FOUND';
      end if;
    end if;
  exception when check_violation or not_null_violation or invalid_text_representation or datetime_field_overflow then
    raise exception 'a target needs a name, a metric, a period and a positive goal' using errcode = '22023', hint = 'GOAL_INVALID';
  end;
  return (select (to_jsonb(x) || jsonb_build_object('goal', x."goal"::text, 'actual', x."actual"::text)) from "better_supabase"."goals" x where x."id" = v_id);
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
      insert into "better_supabase"."job_openings" ("tenant_id", "title", "team_id", "location", "employment_type", "description", "hiring_manager_id", "status")
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
        "hiring_manager_id" = case when save_job.attrs ? 'hiringManagerId' then (save_job.attrs ->> 'hiringManagerId')::uuid else x."hiring_manager_id" end,
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
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_person.tenant, 'contacts.write'), false)) then
    raise exception 'not allowed to change companies and people' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  if jsonb_typeof(coalesce(save_person.attrs, '{}')) <> 'object' then
    raise exception 'attrs must be an object' using errcode = '22023', hint = 'PARTY_ATTRS_INVALID';
  end if;
  if save_person.attrs ? 'lifecycle' and not (save_person.attrs ->> 'lifecycle' = any ('{lead,mql,sql,opportunity,customer}'::text[])) then
    raise exception 'unknown lifecycle stage' using errcode = '22023', hint = 'PARTY_LIFECYCLE_INVALID';
  end if;
  if save_person.attrs ? 'mode' and coalesce(lower(trim(save_person.attrs ->> 'mode')), '') not in ('external', 'tenant') then
    raise exception 'a person is external or tenant' using errcode = '22023', hint = 'PARTY_MODE_INVALID';
  end if;
  if v_created and lower(trim(save_person.attrs ->> 'mode')) = 'tenant' and nullif(save_person.attrs ->> 'userId', '') is null then
    raise exception 'a tenant person needs a userId' using errcode = '22023', hint = 'PARTY_MODE_INVALID';
  end if;
  if save_person.attrs ->> 'customerTermsId' is not null and not exists (select 1 from "better_supabase"."payment_terms" pt where pt."id"::text = save_person.attrs ->> 'customerTermsId' and pt."tenant_id" = save_person.tenant) then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_person.attrs ->> 'supplierTermsId' is not null and not exists (select 1 from "better_supabase"."payment_terms" pt where pt."id"::text = save_person.attrs ->> 'supplierTermsId' and pt."tenant_id" = save_person.tenant) then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_person.attrs ->> 'creditBlock' is not null and lower(trim(save_person.attrs ->> 'creditBlock')) not in ('none', 'soft', 'hard') then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_person.attrs ->> 'language' is not null and nullif(trim(save_person.attrs ->> 'language'), '') is not null and trim(save_person.attrs ->> 'language') !~ '^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$' then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_person.attrs ->> 'creditLimit' is not null and save_person.attrs ->> 'creditLimit' !~ '^[0-9]{1,18}$' then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_person.attrs ->> 'creditCurrency' is not null and upper(trim(save_person.attrs ->> 'creditCurrency')) !~ '^[A-Z]{3}$' then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_person.attrs ? 'creditLimit' <> save_person.attrs ? 'creditCurrency' then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_person.attrs ? 'creditLimit' and (save_person.attrs ->> 'creditLimit' is null) <> (nullif(trim(save_person.attrs ->> 'creditCurrency'), '') is null) then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
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
      insert into "better_supabase"."people" ("tenant_id", "name", "email", "phone", "title", "mode", "lifecycle", "owner_id", "user_id", "customer_terms_id", "supplier_terms_id", "credit_limit", "credit_currency", "credit_block", "language", "created_by")
      values (save_person.tenant, nullif(trim(save_person.attrs ->> 'name'), ''), lower(nullif(trim(save_person.attrs ->> 'email'), '')), nullif(trim(save_person.attrs ->> 'phone'), ''), nullif(trim(save_person.attrs ->> 'title'), ''), coalesce(lower(nullif(trim(save_person.attrs ->> 'mode'), '')), 'external'), coalesce(nullif(trim(save_person.attrs ->> 'lifecycle'), ''), ('{lead,mql,sql,opportunity,customer}'::text[])[1]), nullif(save_person.attrs ->> 'ownerId', '')::uuid, nullif(save_person.attrs ->> 'userId', '')::uuid, nullif(save_person.attrs ->> 'customerTermsId', '')::uuid, nullif(save_person.attrs ->> 'supplierTermsId', '')::uuid, nullif(trim(save_person.attrs ->> 'creditLimit'), '')::bigint, upper(nullif(trim(save_person.attrs ->> 'creditCurrency'), '')), lower(nullif(trim(save_person.attrs ->> 'creditBlock'), '')), nullif(trim(save_person.attrs ->> 'language'), ''), auth.uid())
      returning "id", "owner_id" into v_id, v_owner;
    else
      select x."owner_id" into v_previous_owner from "better_supabase"."people" x
      where x."id" = save_person.person and x."tenant_id" = save_person.tenant;
      update "better_supabase"."people" x set "name" = case when save_person.attrs ? 'name' then coalesce(nullif(trim(save_person.attrs ->> 'name'), ''), x."name") else x."name" end,
        "email" = case when save_person.attrs ? 'email' then lower(nullif(trim(save_person.attrs ->> 'email'), '')) else x."email" end,
        "phone" = case when save_person.attrs ? 'phone' then nullif(trim(save_person.attrs ->> 'phone'), '') else x."phone" end,
        "title" = case when save_person.attrs ? 'title' then nullif(trim(save_person.attrs ->> 'title'), '') else x."title" end,
        "mode" = case when save_person.attrs ? 'mode' then coalesce(lower(nullif(trim(save_person.attrs ->> 'mode'), '')), x."mode") else x."mode" end,
        "lifecycle" = case when save_person.attrs ? 'lifecycle' then coalesce(nullif(trim(save_person.attrs ->> 'lifecycle'), ''), x."lifecycle") else x."lifecycle" end,
        "owner_id" = case when save_person.attrs ? 'ownerId' then nullif(save_person.attrs ->> 'ownerId', '')::uuid else x."owner_id" end,
        "user_id" = case when save_person.attrs ? 'userId' then nullif(save_person.attrs ->> 'userId', '')::uuid else x."user_id" end,
        "customer_terms_id" = case when save_person.attrs ? 'customerTermsId' then nullif(save_person.attrs ->> 'customerTermsId', '')::uuid else x."customer_terms_id" end,
        "supplier_terms_id" = case when save_person.attrs ? 'supplierTermsId' then nullif(save_person.attrs ->> 'supplierTermsId', '')::uuid else x."supplier_terms_id" end,
        "credit_limit" = case when save_person.attrs ? 'creditLimit' then nullif(trim(save_person.attrs ->> 'creditLimit'), '')::bigint else x."credit_limit" end,
        "credit_currency" = case when save_person.attrs ? 'creditCurrency' then upper(nullif(trim(save_person.attrs ->> 'creditCurrency'), '')) else x."credit_currency" end,
        "credit_block" = case when save_person.attrs ? 'creditBlock' then lower(nullif(trim(save_person.attrs ->> 'creditBlock'), '')) else x."credit_block" end,
        "language" = case when save_person.attrs ? 'language' then nullif(trim(save_person.attrs ->> 'language'), '') else x."language" end,
        "updated_at" = now()
      where x."id" = save_person.person and x."tenant_id" = save_person.tenant and x."merged_into" is null
      returning x."owner_id" into v_owner;
      if not found then
        raise exception 'person not found' using errcode = 'P0002', hint = 'PARTY_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'another person has this email' using errcode = '23505', hint = 'PARTY_EMAIL_TAKEN';
  end;
  select to_jsonb(x) || jsonb_build_object('roles', x."roles", 'customer_terms_id', x."customer_terms_id", 'supplier_terms_id', x."supplier_terms_id", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'credit_block', x."credit_block", 'supplier_status', x."supplier_status", 'language', x."language") into v_row from "better_supabase"."people" x where x."id" = v_id;
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

CREATE OR REPLACE FUNCTION better_supabase.save_project (
  tenant  uuid,
  project uuid,
  attrs   jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid := save_project.project;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', save_project.tenant, 'tasks.manage'), false)) then
    raise exception 'not allowed to manage projects and iterations' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  begin
    if v_id is null then
      insert into "better_supabase"."work_projects" ("tenant_id", "key", "name", "owner_id", "status", "start_on", "target_on", "budget_amount", "budget_currency", "budget_hours")
      values (save_project.tenant, upper(save_project.attrs ->> 'key'), save_project.attrs ->> 'name', (save_project.attrs ->> 'ownerId')::uuid,
        coalesce(save_project.attrs ->> 'status', 'planned'), (save_project.attrs ->> 'startOn')::date, (save_project.attrs ->> 'targetOn')::date,
        (save_project.attrs ->> 'budgetAmount')::bigint, upper(save_project.attrs ->> 'budgetCurrency'), (save_project.attrs ->> 'budgetHours')::numeric)
      returning "id" into v_id;
    else
      update "better_supabase"."work_projects" x set
        "key" = coalesce(upper(save_project.attrs ->> 'key'), x."key"),
        "name" = coalesce(save_project.attrs ->> 'name', x."name"),
        "owner_id" = case when save_project.attrs ? 'ownerId' then (save_project.attrs ->> 'ownerId')::uuid else x."owner_id" end,
        "status" = coalesce(save_project.attrs ->> 'status', x."status"),
        "start_on" = case when save_project.attrs ? 'startOn' then (save_project.attrs ->> 'startOn')::date else x."start_on" end,
        "target_on" = case when save_project.attrs ? 'targetOn' then (save_project.attrs ->> 'targetOn')::date else x."target_on" end,
        "budget_amount" = case when save_project.attrs ? 'budgetAmount' then (save_project.attrs ->> 'budgetAmount')::bigint else x."budget_amount" end,
        "budget_currency" = case when save_project.attrs ? 'budgetCurrency' then upper(save_project.attrs ->> 'budgetCurrency') else x."budget_currency" end,
        "budget_hours" = case when save_project.attrs ? 'budgetHours' then (save_project.attrs ->> 'budgetHours')::numeric else x."budget_hours" end,
        "archived_at" = case when save_project.attrs ? 'archived' then (case when (save_project.attrs ->> 'archived')::boolean then coalesce(x."archived_at", now()) end) else x."archived_at" end,
        "updated_at" = now()
      where x."id" = v_id and x."tenant_id" = save_project.tenant;
      if not found then
        raise exception 'project not found' using errcode = 'P0002', hint = 'TASK_PROJECT_NOT_FOUND';
      end if;
    end if;
    if exists (
      select 1 from "better_supabase"."work_projects" x
      where x."id" = v_id and x."budget_amount" is not null and x."budget_currency" is null
    ) then
      raise exception 'a budget amount needs a currency' using errcode = '22023', hint = 'TASK_PROJECT_INVALID';
    end if;
  exception when unique_violation then
    raise exception 'another project has this key' using errcode = '23505', hint = 'TASK_PROJECT_KEY_TAKEN';
  when check_violation or not_null_violation then
    raise exception 'a project needs a key of capitals and a name, and ends after it starts' using errcode = '22023', hint = 'TASK_PROJECT_INVALID';
  end;

  perform "better_supabase"."accounting_sync_dimension_value"(x."tenant_id", 'project', 'Project', x."id"::text, x."key" || ' ' || x."name", x."archived_at" is not null)
  from "better_supabase"."work_projects" x where x."id" = v_id;
  return (select to_jsonb(x) || jsonb_build_object('budget_amount', x."budget_amount"::text) || jsonb_build_object('progress', (
      select case when count(*) = 0 then null else round(100.0 * count(*) filter (where y."state" = 'completed') / count(*) filter (where y."state" <> 'canceled')) end
      from "better_supabase"."work_items" y where y."project_id" = x."id" and y."archived_at" is null
    )) from "better_supabase"."work_projects" x where x."id" = v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.send_quote (
  quote uuid,
  actor jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."quotes";
  v_token text := encode(extensions.gen_random_bytes(24), 'hex');
  v_version uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = send_quote.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false)) for update;
  
  if v_row."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if not (v_row."status" in ('draft', 'changes_requested') or v_row."status" in ('rejected', 'withdrawn', 'expired')) then
    raise exception 'the quote was already sent; revise it to send a new version' using errcode = '55000', hint = 'QUOTE_NOT_EDITABLE';
  end if;
  if not exists (select 1 from "better_supabase"."quote_lines" x where x."parent_id" = v_row."id") then
    raise exception 'a quote needs a line before it is sent' using errcode = '23514', hint = 'QUOTE_EMPTY';
  end if;
  if send_quote.actor is not null then
    if jsonb_typeof(send_quote.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(send_quote.actor ->> 'ip', '')::inet, nullif(send_quote.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(send_quote.actor::text, ''), true);
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_quote_send"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  update "better_supabase"."quotes" x set "status" = 'sent', "sent_at" = now(), "token_hash" = encode(extensions.digest(v_token, 'sha256'), 'hex'),
    "revision" = case when exists (select 1 from "better_supabase"."quote_versions" v where v."quote_id" = x."id" and v."revision" = x."revision") then x."revision" + 1 else x."revision" end,
    "decided_at" = null, "decided_by" = null, "decision_note" = null, "decider_id" = null, "decided_ip" = null, "decided_user_agent" = null, "valid_until" = case when x."status" in ('rejected', 'withdrawn', 'expired') then greatest(x."valid_until", current_date + 30) else x."valid_until" end, "viewed_at" = case when x."status" in ('rejected', 'withdrawn', 'expired') then null else x."viewed_at" end, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  insert into "better_supabase"."quote_versions" ("tenant_id", "quote_id", "revision", "snapshot", "total", "currency", "published_by")
  values (v_row."tenant_id", v_row."id", v_row."revision", (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'unit', ql."unit", 'discountKind', ql."discount_kind", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb)), v_row."total", v_row."currency", coalesce(auth.uid(), nullif(send_quote.actor ->> 'id', '')::uuid))
  returning "id" into v_version;
  perform "better_supabase".emit_event('quote.sent', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'revision', v_row."revision"), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_quote_send"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'unit', ql."unit", 'discountKind', ql."discount_kind", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb)) || jsonb_build_object('token', v_token);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_deal_contacts (
  deal     uuid,
  contacts jsonb
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_deal uuid := set_deal_contacts.deal;
  v_item jsonb;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."deals" x where x."id" = v_deal and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.write'), false) and (true or coalesce(x."owner_id" = auth.uid(), false)
      or coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.manage'), false)
      or exists (select 1 from "better_supabase"."deal_members" mm where mm."deal_id" = x."id" and mm."user_id" = auth.uid()))));
  if v_tenant is null then
    raise exception 'no such deal you can edit' using errcode = 'P0002', hint = 'DEAL_NOT_FOUND';
  end if;
  if jsonb_typeof(coalesce(set_deal_contacts.contacts, '[]')) <> 'array' then
    raise exception 'contacts must be a list of { type, id }' using errcode = '22023', hint = 'DEAL_CONTACTS_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(set_deal_contacts.contacts) loop
    if not (case coalesce(v_item ->> 'type', 'person')
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
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
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
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      else false
    end and "better_supabase"."can_subject"(coalesce(v_item ->> 'type', 'person'), (v_item ->> 'id'), 'read')) then
      raise exception 'a contact is unknown or not readable in this organization' using errcode = '42501', hint = 'DEAL_CONTACT_FORBIDDEN';
    end if;
  end loop;
  if (select count(*) from jsonb_array_elements(set_deal_contacts.contacts) x where coalesce((x.value ->> 'primary')::boolean, false)) > 1 then
    raise exception 'a deal has one primary contact' using errcode = '22023', hint = 'DEAL_CONTACTS_INVALID';
  end if;
  delete from "better_supabase"."deal_contacts" x where x."deal_id" = v_deal;
  insert into "better_supabase"."deal_contacts" ("tenant_id", "deal_id", "contact_type", "contact_id", "role", "is_primary")
  select v_tenant, v_deal, coalesce(x.value ->> 'type', 'person'), x.value ->> 'id', x.value ->> 'role', coalesce((x.value ->> 'primary')::boolean, false)
  from jsonb_array_elements(set_deal_contacts.contacts) x
  on conflict do nothing;
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_deal_lines (
  parent uuid,
  lines  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_parent uuid := set_deal_lines.parent;
  v_tenant uuid;
  v_currency text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."currency" into v_tenant, v_currency from "better_supabase"."deals" x where x."id" = v_parent and not (x."locked");
  if v_tenant is null then
    raise exception 'no such record, or its lines are locked' using errcode = 'P0002', hint = 'LINES_RECORD_INVALID';
  end if;
  if not exists (select 1 from "better_supabase"."deals" x where x."id" = v_parent and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.write'), false) and (true or coalesce(x."owner_id" = auth.uid(), false)
      or coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.manage'), false)
      or exists (select 1 from "better_supabase"."deal_members" mm where mm."deal_id" = x."id" and mm."user_id" = auth.uid()))))) then
    raise exception 'no such deal you can edit' using errcode = 'P0002', hint = 'DEAL_NOT_FOUND';
  end if;
  if jsonb_typeof(coalesce(set_deal_lines.lines, '[]')) <> 'array' then
    raise exception 'lines must be a list' using errcode = '22023', hint = 'LINES_INVALID';
  end if;
  if exists (select 1 from jsonb_array_elements(set_deal_lines.lines) x where x.value ? 'currency' and x.value ->> 'currency' is distinct from v_currency) then
    raise exception 'every line must be in the record''s currency' using errcode = '22023', hint = 'LINES_CURRENCY';
  end if;
  delete from "better_supabase"."deal_lines" l where l."parent_id" = v_parent;
  begin
    insert into "better_supabase"."deal_lines" ("tenant_id", "parent_id", "product_type", "product_id", "description", "quantity", "unit_amount", "discount_bps", "tax_rate_bps", "tax_code", "position")
    select v_tenant,
      v_parent,
      x.value -> 'product' ->> 'type',
      x.value -> 'product' ->> 'id',
      x.value ->> 'description',
      coalesce((x.value ->> 'quantity')::numeric, 1),
      (x.value ->> 'unitAmount')::bigint,
      coalesce((x.value ->> 'discountBps')::integer, 0),
      coalesce((x.value ->> 'taxRateBps')::integer, 0),
      x.value ->> 'taxCode',
      x.ordinality::integer
    from jsonb_array_elements(coalesce(set_deal_lines.lines, '[]')) with ordinality x;
  exception when check_violation or not_null_violation or invalid_text_representation or numeric_value_out_of_range then
    raise exception 'every line needs a description, a positive quantity and a unit amount' using errcode = '22023', hint = 'LINES_INVALID';
  end;
  perform "better_supabase"."set_deal_lines_recount"(v_parent);
  return (select jsonb_build_object(
    'listTotal', x."list_total"::text, 'discountTotal', x."discount_total"::text,
    'subtotal', x."subtotal"::text, 'taxTotal', x."tax_total"::text, 'total', x."total"::text,
    'currency', x."currency")
    from "better_supabase"."deals" x where x."id" = v_parent);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_deal_members (
  deal    uuid,
  members jsonb
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_deal uuid := set_deal_members.deal;
  v_user uuid;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."deals" x where x."id" = v_deal and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.write'), false) and (true or coalesce(x."owner_id" = auth.uid(), false)
      or coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.manage'), false)
      or exists (select 1 from "better_supabase"."deal_members" mm where mm."deal_id" = x."id" and mm."user_id" = auth.uid()))));
  if v_tenant is null then
    raise exception 'no such deal you can edit' using errcode = 'P0002', hint = 'DEAL_NOT_FOUND';
  end if;
  if jsonb_typeof(coalesce(set_deal_members.members, '[]')) <> 'array' then
    raise exception 'members must be a list of { userId, role }' using errcode = '22023', hint = 'DEAL_MEMBERS_INVALID';
  end if;
  delete from "better_supabase"."deal_members" x where x."deal_id" = v_deal;
  insert into "better_supabase"."deal_members" ("tenant_id", "deal_id", "user_id", "role")
  select v_tenant, v_deal, (x.value ->> 'userId')::uuid, x.value ->> 'role'
  from jsonb_array_elements(set_deal_members.members) x
  on conflict do nothing;
  get diagnostics v_count = row_count;
  for v_user in select (x.value ->> 'userId')::uuid from jsonb_array_elements(set_deal_members.members) x loop
    insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
    values (v_tenant, v_user, 'deal', v_deal::text, 'participating')
    on conflict do nothing;
  end loop;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.sign_off_appraisal (
  appraisal_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."appraisals";
  v_cycle "better_supabase"."appraisal_cycles";
  v_payload jsonb;
  v_approval jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."appraisals" x where x."id" = sign_off_appraisal.appraisal_id for update;
  if not found then
    raise exception 'no such appraisal' using errcode = 'P0002', hint = 'APPRAISALS_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'appraisals.manage'), false))) then
    raise exception 'not allowed to sign off appraisals' using errcode = '42501', hint = 'APPRAISALS_FORBIDDEN';
  end if;
  select * into v_cycle from "better_supabase"."appraisal_cycles" x where x."id" = v_row."cycle_id";
  if v_cycle."status" <> 'open' or v_row."status" not in ('reviewed', 'calibrated') then
    raise exception 'only a reviewed or calibrated appraisal in an open cycle is signed off' using errcode = '55000', hint = 'APPRAISALS_STATE';
  end if;
  v_payload := jsonb_build_object('appraisalId', v_row."id", 'cycleId', v_row."cycle_id", 'subjectUserId', v_row."appraisee_id",
    'rating', coalesce(v_row."calibrated_rating"::numeric, v_row."rating")::text,
    'competencies', "better_supabase"."appraisal_json"(v_row."id", true) -> 'competencies');
  v_approval := "better_supabase"."open_approval"(
    v_row."tenant_id", 'appraisal', v_row."id"::text, 'sign_off',
    coalesce("better_supabase"."approval_effective_policy"(v_row."tenant_id", 'appraisal', 'sign_off', v_payload), '{"steps":[{"approvers":{"permission":"appraisals.manage"},"required":1}],"selfApproval":false,"expiresIn":null,"run":null}'::jsonb),
    null, v_payload
  );
  update "better_supabase"."appraisals" x
  set "status" = 'awaiting_signoff', "approval_id" = (v_approval ->> 'id')::uuid, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  return "better_supabase"."appraisal_json"(v_row."id", true);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.submit_scorecard (
  application    uuid,
  rating         integer,
  recommendation text,
  notes          text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."applications";
  v_card "better_supabase"."application_scorecards";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."applications" x where x."id" = submit_scorecard.application;
  if v_row."id" is null or not (((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'hiring.write'), false)) or exists (
    select 1 from "better_supabase"."interviews" y where y."application_id" = v_row."id" and auth.uid() = any (y."interviewer_user_ids"))) then
    raise exception 'no such application you can review' using errcode = 'P0002', hint = 'HIRING_APPLICATION_NOT_FOUND';
  end if;
  begin
    insert into "better_supabase"."application_scorecards" ("tenant_id", "application_id", "stage_id", "reviewer_id", "rating", "recommendation", "notes")
    values (v_row."tenant_id", v_row."id", v_row."stage_id", auth.uid(), submit_scorecard.rating, submit_scorecard.recommendation, submit_scorecard.notes)
    on conflict ("application_id", "stage_id", "reviewer_id") do update set
      "rating" = excluded."rating", "recommendation" = excluded."recommendation",
      "notes" = excluded."notes", "submitted_at" = now()
    returning * into v_card;
  exception when check_violation or not_null_violation then
    raise exception 'a scorecard needs a rating from 1 to 4 and a recommendation' using errcode = '22023', hint = 'HIRING_SCORECARD_INVALID';
  end;
  perform "better_supabase".emit_event('scorecard.submitted', jsonb_build_object('organizationId', v_row."tenant_id", 'applicationId', v_row."id", 'subjectType', 'application', 'subjectId', v_row."id"::text, 'jobId', v_row."job_id", 'candidateType', v_row."candidate_type", 'candidateId', v_row."candidate_id", 'reviewerId', v_card."reviewer_id", 'recommendation', v_card."recommendation"), 'applications/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/hiring');
  return to_jsonb(v_card);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.switch_ai_branch (
  chat       uuid,
  message_id text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_chat "better_supabase"."ai_chats";
  v_leaf text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_chat from "better_supabase"."ai_chats" x where x."id" = switch_ai_branch.chat for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_chat."owner_id" = (select auth.uid()), false) or (v_chat."visibility" <> 'private' and exists (select 1 from "better_supabase"."ai_chat_participants" pa where pa."chat_id" = v_chat."id" and pa."role"::text in ('editor') and ((((pa."kind"::text = 'user' and pa."user_id" = (select auth.uid())) or (pa."kind"::text = 'team' and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = pa."team_id"::text and tm."user_id" = (select auth.uid())))) and (v_chat."organization_id" is null or v_chat."organization_id" in (select better_supabase.member_organization_ids()))) or (pa."kind"::text = 'customer' and pa."customer_id" = (select auth.uid()) and ((v_chat."organization_id")::text, ('ai-chat')::text, (v_chat."id"::text)::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g)))))) then
    raise exception 'No chat %', switch_ai_branch.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  if not exists (select 1 from "better_supabase"."ai_messages" x where x."chat_id" = switch_ai_branch.chat and x."id" = switch_ai_branch.message_id) then
    raise exception 'No message %', switch_ai_branch.message_id using errcode = 'P0002', hint = 'AI_MESSAGE_NOT_FOUND';
  end if;
  with recursive down as (
    select switch_ai_branch.message_id as id, 0 as depth
    union all
    select (
      select c."id" from "better_supabase"."ai_messages" c
      where c."chat_id" = switch_ai_branch.chat and c."parent_id" = down.id
      order by c."seq" desc limit 1
    ), down.depth + 1
    from down
    where down.id is not null and down.depth < 10000
  )
  select d.id into v_leaf from down d where d.id is not null order by d.depth desc limit 1;
  update "better_supabase"."ai_chats" x set "current_leaf_id" = v_leaf, "updated_at" = now() where x."id" = switch_ai_branch.chat;
  perform "better_supabase"."ai_chat_notify"(switch_ai_branch.chat, null, 'leaf.changed', jsonb_build_object('leafId', v_leaf), false);
  return jsonb_build_object('leaf_id', v_leaf);
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
  insert into "better_supabase"."forecast_snapshot_deals" ("snapshot_id", "tenant_id", "deal_id", "name", "owner_id", "stage_id", "forecast_category", "outcome", "amount", "expected_close_on", "closed_at")
  select v_row."id", x."tenant_id", x."id", x."name", x."owner_id", x."stage_id", x."forecast_category"::text, x."outcome"::text, x."amount", x."expected_close_on", x."closed_at"
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
  select x."tenant_id", x."type", x."owner_id" into v_tenant, v_type, v_previous_owner
  from "better_supabase"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false));
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
  if exists (select 1 from "better_supabase"."activities" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.manage'), false)) and (x."locked_at" <= now() or x."marked_error_at" is not null)) then
    raise exception 'the engagement is locked: add an addendum with amend_activity instead' using errcode = '55000', hint = 'ACTIVITY_LOCKED';
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
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
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
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
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
  delete from "better_supabase"."engagement_subjects" x where x."activity_id" = v_id;
  insert into "better_supabase"."engagement_subjects" ("tenant_id", "activity_id", "subject_type", "subject_id", "position")
  select v_tenant, v_id, s.value ->> 'type', s.value ->> 'id', s.ordinality::integer
  from jsonb_array_elements(coalesce(update_activity.subjects, '[]')) with ordinality s
  on conflict do nothing;
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  else
    v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = v_id), '[]'::jsonb);
    v_first := v_subjects -> 0;
  end if;
  perform "better_supabase".emit_event('activity.updated', jsonb_build_object('organizationId', v_tenant, 'engagementId', v_id, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects), 'engagements/' || v_id::text, (v_tenant::text)::text, null, 'better-supabase/activities');
  if v_owner is not null and v_owner is distinct from auth.uid() and v_owner is distinct from v_previous_owner then
    if better_supabase.import_run() is null then
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
  end if;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."activity_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."activities" x where x."id" = v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_deals (
  changes jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_change jsonb;
  v_deal uuid;
  v_field text;
  v_row "better_supabase"."deals";
  v_accepted jsonb := '[]';
  v_rejected jsonb := '[]';
  v_hint text;
  v_reason text;
  v_touched uuid[] := '{}';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(coalesce(update_deals.changes, '[]')) <> 'array' then
    raise exception 'changes must be a list of { dealId, field, value }' using errcode = '22023', hint = 'DEAL_CHANGES_INVALID';
  end if;
  for v_change in select value from jsonb_array_elements(update_deals.changes) loop
    v_field := v_change ->> 'field';
    begin
      v_deal := (v_change ->> 'dealId')::uuid;
      select * into v_row from "better_supabase"."deals" x where x."id" = v_deal and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.write'), false) and (true or coalesce(x."owner_id" = auth.uid(), false)
      or coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.manage'), false)
      or exists (select 1 from "better_supabase"."deal_members" mm where mm."deal_id" = x."id" and mm."user_id" = auth.uid())))) and x."archived_at" is null;
      if v_row."id" is null then
        raise exception 'no such deal you can edit' using errcode = 'P0002', hint = 'DEAL_NOT_FOUND';
      end if;
      if v_field = 'company' and jsonb_typeof(v_change -> 'value') = 'object' then
        if (v_change -> 'value' ->> 'id') is not null and not (case (v_change -> 'value' ->> 'type')
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'rfq' then exists (select 1 from "better_supabase"."rfqs" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'till' then exists (select 1 from "better_supabase"."tills" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'meeting' then exists (select 1 from "better_supabase"."meetings" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'meeting_decision' then exists (select 1 from "better_supabase"."meeting_decisions" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'maintenance_plan' then exists (select 1 from "better_supabase"."maintenance_plans" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'dam_usage_right' then exists (select 1 from "better_supabase"."dam_usage_rights" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'lims_sample' then exists (select 1 from "better_supabase"."lims_samples" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = ((v_change -> 'value' ->> 'id'))::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      else false
    end and "better_supabase"."can_subject"((v_change -> 'value' ->> 'type'), (v_change -> 'value' ->> 'id'), 'read')) then
    raise exception 'the company is unknown or not readable in this organization' using errcode = '42501', hint = 'DEAL_COMPANY_FORBIDDEN';
  end if;
      end if;
      if v_field in ('amount', 'existingAmount') and jsonb_typeof(v_change -> 'value') = 'object' then
        if upper(v_change -> 'value' ->> 'currency') is distinct from v_row."currency" then
          raise exception 'an amount must be in the deal''s currency' using errcode = '22023', hint = 'DEAL_CURRENCY_MISMATCH';
        end if;
        v_change := jsonb_set(v_change, '{value}', v_change -> 'value' -> 'amount');
      end if;
      declare
    v_hook regprocedure := to_regprocedure('"public"."before_deal_update"(uuid, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::jsonb)', v_hook::oid::regproc)
        using v_deal, v_field, v_change -> 'value';
    end if;
  end;
      case v_field
      when 'name' then
        update "better_supabase"."deals" x set "name" = trim(v_change -> 'value' #>> '{}') where x."id" = v_deal returning * into v_row;
      when 'motion' then
        update "better_supabase"."deals" x set "motion" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'priority' then
        update "better_supabase"."deals" x set "priority" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'ownerId' then
        update "better_supabase"."deals" x set "owner_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_deal returning * into v_row;
      when 'product' then
        update "better_supabase"."deals" x set "product" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'seats' then
        update "better_supabase"."deals" x set "seats" = (v_change -> 'value' #>> '{}')::integer where x."id" = v_deal returning * into v_row;
      when 'amount' then
        update "better_supabase"."deals" x set "amount" = (v_change -> 'value' #>> '{}')::bigint where x."id" = v_deal returning * into v_row;
      when 'existingAmount' then
        update "better_supabase"."deals" x set "existing_amount" = (v_change -> 'value' #>> '{}')::bigint where x."id" = v_deal returning * into v_row;
      when 'currency' then
        update "better_supabase"."deals" x set "currency" = upper(v_change -> 'value' #>> '{}') where x."id" = v_deal returning * into v_row;
      when 'valuePeriod' then
        update "better_supabase"."deals" x set "value_period" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'amountSource' then
        update "better_supabase"."deals" x set "amount_source" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'stageId' then
        update "better_supabase"."deals" x set "stage_id" = (v_change -> 'value' #>> '{}')::uuid where x."id" = v_deal returning * into v_row;
      when 'probability' then
        update "better_supabase"."deals" x set "probability" = (v_change -> 'value' #>> '{}')::smallint where x."id" = v_deal returning * into v_row;
      when 'forecast' then
        update "better_supabase"."deals" x set "forecast_category" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'closeOn' then
        update "better_supabase"."deals" x set "expected_close_on" = (v_change -> 'value' #>> '{}')::date where x."id" = v_deal returning * into v_row;
      when 'nextStep' then
        update "better_supabase"."deals" x set "next_step" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'nextAt' then
        update "better_supabase"."deals" x set "next_at" = (v_change -> 'value' #>> '{}')::timestamptz where x."id" = v_deal returning * into v_row;
      when 'nextKind' then
        update "better_supabase"."deals" x set "next_kind" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'flags' then
        update "better_supabase"."deals" x set "flags" = coalesce(array(select jsonb_array_elements_text(case jsonb_typeof(v_change -> 'value') when 'array' then v_change -> 'value' else '[]' end)), '{}') where x."id" = v_deal returning * into v_row;
      when 'source' then
        update "better_supabase"."deals" x set "source" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'note' then
        update "better_supabase"."deals" x set "note" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'lostReason' then
        update "better_supabase"."deals" x set "lost_reason" = nullif(trim(v_change -> 'value' #>> '{}'), '') where x."id" = v_deal returning * into v_row;
      when 'company' then
        update "better_supabase"."deals" x set "company_type" = v_change -> 'value' ->> 'type', "company_id" = v_change -> 'value' ->> 'id' where x."id" = v_deal returning * into v_row;
      else
        raise exception 'that field can''t be written' using errcode = '22023', hint = 'DEAL_FIELD_UNKNOWN';
      end case;
  if v_row."motion" is not null and not (v_row."motion" = any ('{new_logo,expansion,renewal}'::text[])) then
    raise exception 'unknown motion' using errcode = '22023', hint = 'DEAL_MOTION_INVALID';
  end if;
  if v_row."priority" is not null and not (v_row."priority" = any ('{hot,warm,cold}'::text[])) then
    raise exception 'unknown priority' using errcode = '22023', hint = 'DEAL_PRIORITY_INVALID';
  end if;
      v_accepted := v_accepted || jsonb_build_array(jsonb_build_object('dealId', v_deal, 'field', v_field));
      v_touched := array_append(v_touched, v_deal);
      declare
    v_hook regprocedure := to_regprocedure('"public"."after_deal_update"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_deal, v_field;
    end if;
  end;
    exception when others then
      get stacked diagnostics v_hint = pg_exception_hint, v_reason = message_text;
      v_rejected := v_rejected || jsonb_build_array(jsonb_build_object('dealId', v_change ->> 'dealId', 'field', v_field, 'hint', nullif(v_hint, ''), 'reason', v_reason));
    end;
  end loop;
  for v_row in select * from "better_supabase"."deals" x where x."id" = any (v_touched) loop
    perform "better_supabase".emit_event('deal.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'dealId', v_row."id", 'subjectType', 'deal', 'subjectId', v_row."id"::text, 'name', v_row."name", 'fields', (select jsonb_agg(distinct a ->> 'field') from jsonb_array_elements(v_accepted) a where (a ->> 'dealId')::uuid = v_row."id")), 'deals/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/deals');
  end loop;
  return jsonb_build_object('accepted', v_accepted, 'rejected', v_rejected);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_quote (
  quote uuid,
  attrs jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."quotes";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = update_quote.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false));
  if v_row."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if not (v_row."status" in ('draft', 'changes_requested')) then
    raise exception 'only a draft quote, or one with changes requested, can change' using errcode = '55000', hint = 'QUOTE_NOT_EDITABLE';
  end if;
  if (update_quote.attrs -> 'company' ->> 'id') is not null and not (case coalesce(update_quote.attrs -> 'company' ->> 'type', 'company')
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'rfq' then exists (select 1 from "better_supabase"."rfqs" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'till' then exists (select 1 from "better_supabase"."tills" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'meeting' then exists (select 1 from "better_supabase"."meetings" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'meeting_decision' then exists (select 1 from "better_supabase"."meeting_decisions" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'maintenance_plan' then exists (select 1 from "better_supabase"."maintenance_plans" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'dam_usage_right' then exists (select 1 from "better_supabase"."dam_usage_rights" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'lims_sample' then exists (select 1 from "better_supabase"."lims_samples" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = ((update_quote.attrs -> 'company' ->> 'id'))::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      else false
    end and "better_supabase"."can_subject"(coalesce(update_quote.attrs -> 'company' ->> 'type', 'company'), (update_quote.attrs -> 'company' ->> 'id'), 'read')) then
    raise exception 'the company is unknown or not readable in this organization' using errcode = '42501', hint = 'QUOTE_COMPANY_FORBIDDEN';
  end if;
  if (update_quote.attrs -> 'contact' ->> 'id') is not null and not (case coalesce(update_quote.attrs -> 'contact' ->> 'type', 'person')
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'rfq' then exists (select 1 from "better_supabase"."rfqs" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'till' then exists (select 1 from "better_supabase"."tills" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'meeting' then exists (select 1 from "better_supabase"."meetings" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'meeting_decision' then exists (select 1 from "better_supabase"."meeting_decisions" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'maintenance_plan' then exists (select 1 from "better_supabase"."maintenance_plans" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'dam_usage_right' then exists (select 1 from "better_supabase"."dam_usage_rights" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'lims_sample' then exists (select 1 from "better_supabase"."lims_samples" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = ((update_quote.attrs -> 'contact' ->> 'id'))::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      else false
    end and "better_supabase"."can_subject"(coalesce(update_quote.attrs -> 'contact' ->> 'type', 'person'), (update_quote.attrs -> 'contact' ->> 'id'), 'read')) then
    raise exception 'the contact is unknown or not readable in this organization' using errcode = '42501', hint = 'QUOTE_CONTACT_FORBIDDEN';
  end if;
  begin
    update "better_supabase"."quotes" x set
      "title" = coalesce(nullif(trim(update_quote.attrs ->> 'title'), ''), x."title"),
      "currency" = coalesce(upper(update_quote.attrs ->> 'currency'), x."currency"),
      "owner_id" = case when update_quote.attrs ? 'ownerId' then (update_quote.attrs ->> 'ownerId')::uuid else x."owner_id" end,
      "valid_until" = case when update_quote.attrs ? 'validUntil' then (update_quote.attrs ->> 'validUntil')::date else x."valid_until" end,
      "terms" = case when update_quote.attrs ? 'terms' then update_quote.attrs ->> 'terms' else x."terms" end,
      "note" = case when update_quote.attrs ? 'note' then update_quote.attrs ->> 'note' else x."note" end,
      "prices_include_tax" = case when update_quote.attrs ? 'pricesIncludeTax' then coalesce((update_quote.attrs ->> 'pricesIncludeTax')::boolean, false) else x."prices_include_tax" end,
      "discount_bps" = case when update_quote.attrs ? 'discountBps' then coalesce((update_quote.attrs ->> 'discountBps')::integer, 0) else x."discount_bps" end,
      "discount_amount" = case when update_quote.attrs ? 'discountAmount' then coalesce((update_quote.attrs ->> 'discountAmount')::bigint, 0) else x."discount_amount" end,
      "deposit_bps" = case when update_quote.attrs ? 'depositBps' then (update_quote.attrs ->> 'depositBps')::integer else x."deposit_bps" end,
      "deposit_amount" = case when update_quote.attrs ? 'depositAmount' then (update_quote.attrs ->> 'depositAmount')::bigint else x."deposit_amount" end,
      "deposit_required" = case when update_quote.attrs ? 'depositRequired' then coalesce((update_quote.attrs ->> 'depositRequired')::boolean, false) else x."deposit_required" end,
      "company_type" = case when update_quote.attrs ? 'company' then case when update_quote.attrs -> 'company' ->> 'id' is null then null else coalesce(update_quote.attrs -> 'company' ->> 'type', 'company') end else x."company_type" end,
      "company_id" = case when update_quote.attrs ? 'company' then update_quote.attrs -> 'company' ->> 'id' else x."company_id" end,
      "contact_type" = case when update_quote.attrs ? 'contact' then case when update_quote.attrs -> 'contact' ->> 'id' is null then null else coalesce(update_quote.attrs -> 'contact' ->> 'type', 'person') end else x."contact_type" end,
      "contact_id" = case when update_quote.attrs ? 'contact' then update_quote.attrs -> 'contact' ->> 'id' else x."contact_id" end,
      "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  exception when check_violation or invalid_text_representation or datetime_field_overflow or numeric_value_out_of_range then
    raise exception 'a quote field has an invalid value' using errcode = '22023', hint = 'QUOTE_ATTRS_INVALID';
  end;
  if v_row."deposit_bps" is not null and v_row."deposit_amount" is not null then
    raise exception 'a deposit is a share (depositBps) or an amount (depositAmount), not both' using errcode = '22023', hint = 'QUOTE_ATTRS_INVALID';
  end if;
  perform "better_supabase"."set_quote_lines_recount"(v_row."id");
  select * into v_row from "better_supabase"."quotes" x where x."id" = v_row."id";
  perform "better_supabase".emit_event('quote.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier"), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
  return (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'unit', ql."unit", 'discountKind', ql."discount_kind", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.void_referral (
  referral_id uuid,
  reason      text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_ref "better_supabase"."referrals";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_ref from "better_supabase"."referrals" x where x."id" = void_referral.referral_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_ref."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_ref."tenant_id", 'referrals.read'), false))) then
    raise exception 'no such referral' using errcode = 'P0002', hint = 'REFERRAL_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_ref."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_ref."tenant_id", 'referrals.manage'), false))) then
    raise exception 'not allowed to void referrals' using errcode = '42501', hint = 'REFERRAL_FORBIDDEN';
  end if;
  if v_ref."status" = 'void' then
    return jsonb_build_object('id', v_ref."id", 'organizationId', v_ref."tenant_id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_id", 'referredOrganizationId', v_ref."referred_organization_id", 'referredEmail', v_ref."referred_email", 'status', v_ref."status", 'rewardAmount', v_ref."reward_amount"::text, 'rewardUnit', v_ref."reward_unit", 'qualifiedAt', v_ref."qualified_at", 'rewardedAt', v_ref."rewarded_at", 'ledgerTransactionId', v_ref."ledger_transaction_id", 'createdAt', v_ref."created_at");
  end if;
  if v_ref."ledger_transaction_id" is not null then
    perform "better_supabase"."ledger_post"(v_ref."tenant_id", 'referral.reversal',
      (select jsonb_agg(jsonb_build_object('account', e."account_id", 'amount', (-e."amount")::text) order by e."created_at", e."id")
        from "better_supabase"."ledger_entries" e where e."transaction_id" = v_ref."ledger_transaction_id"),
      'referrals', v_ref."id"::text, nullif(trim(void_referral.reason), ''), 'referral-void:' || v_ref."id"::text, null,
      jsonb_build_object('reversal', true), v_ref."ledger_transaction_id");
  end if;
  update "better_supabase"."referrals" x set "status" = 'void', "voided_at" = now()
  where x."id" = v_ref."id" returning * into v_ref;
  perform "better_supabase".emit_event('referral.voided', jsonb_build_object('organizationId', v_ref."tenant_id", 'id', v_ref."id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_id", 'referredOrganizationId', v_ref."referred_organization_id", 'status', v_ref."status"), 'referrals/' || v_ref."id"::text, (v_ref."tenant_id")::text, null, 'better-supabase/referrals');
  perform better_supabase.audit_event(
    event_type => 'referral.voided',
    category => 'data',
    target_type => 'referral',
    record_id => v_ref."id"::text,
    summary => 'referral voided',
    tenant => (v_ref."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_ref."tenant_id", 'id', v_ref."id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_id", 'referredOrganizationId', v_ref."referred_organization_id", 'status', v_ref."status")
  );
  return jsonb_build_object('id', v_ref."id", 'organizationId', v_ref."tenant_id", 'codeId', v_ref."code_id", 'referrerId', v_ref."referrer_id", 'referredUserId', v_ref."referred_id", 'referredOrganizationId', v_ref."referred_organization_id", 'referredEmail', v_ref."referred_email", 'status', v_ref."status", 'rewardAmount', v_ref."reward_amount"::text, 'rewardUnit', v_ref."reward_unit", 'qualifiedAt', v_ref."qualified_at", 'rewardedAt', v_ref."rewarded_at", 'ledgerTransactionId', v_ref."ledger_transaction_id", 'createdAt', v_ref."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.withdraw_consent (
  consent_id uuid,
  reason     text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."consents";
  v_purpose "better_supabase"."consent_purposes";
  v_reason text := nullif(trim(withdraw_consent.reason), '');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."consents" x where x."id" = withdraw_consent.consent_id for update;
  if not found then
    raise exception 'no such consent' using errcode = 'P0002', hint = 'CONSENT_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
      or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'consents.record'), false) and coalesce("better_supabase"."can_subject"(v_row."subject_type", v_row."subject_id", 'read'), false))
      or ((v_row."tenant_id")::text, (v_row."subject_type")::text, (v_row."subject_id")::text) in (select g.tenant, g.party_type, g.party_id from better_supabase.portal_parties() g)
      or exists (select 1 from "better_supabase"."relations" r
      where r."kind" = 'represents' and r."source_type" = 'person'
        and r."tenant_id"::text = (v_row."tenant_id")::text
        and r."target_type" = v_row."subject_type" and r."target_id" = (v_row."subject_id")::text
        and r."data" ->> 'authority' = 'act'
        and (case when r."data" ->> 'valid_from' is null then true
      when pg_input_is_valid(r."data" ->> 'valid_from', 'date') then (r."data" ->> 'valid_from')::date <= current_date
      else false end) and (case when r."data" ->> 'valid_until' is null then true
      when pg_input_is_valid(r."data" ->> 'valid_until', 'date') then (r."data" ->> 'valid_until')::date >= current_date
      else false end)
        and ((v_row."tenant_id")::text, ('person')::text, (r."source_id")::text) in (select g.tenant, g.party_type, g.party_id from better_supabase.portal_parties() g))) or coalesce(v_row."grantor_id" = auth.uid(), false)) then
    if (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
      or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'consents.read'), false) and coalesce("better_supabase"."can_subject"(v_row."subject_type", v_row."subject_id", 'read'), false))
      or ((v_row."tenant_id")::text, (v_row."subject_type")::text, (v_row."subject_id")::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g)
      or ((v_row."tenant_id")::text, (v_row."subject_type")::text, (v_row."subject_id")::text) in (select g.tenant, g.party_type, g.party_id from better_supabase.portal_parties() g)
      or exists (select 1 from "better_supabase"."relations" r
      where r."kind" = 'represents' and r."source_type" = 'person'
        and r."tenant_id"::text = (v_row."tenant_id")::text
        and r."target_type" = v_row."subject_type" and r."target_id" = (v_row."subject_id")::text
        and r."data" ->> 'authority' in ('inform', 'act')
        and (case when r."data" ->> 'valid_from' is null then true
      when pg_input_is_valid(r."data" ->> 'valid_from', 'date') then (r."data" ->> 'valid_from')::date <= current_date
      else false end) and (case when r."data" ->> 'valid_until' is null then true
      when pg_input_is_valid(r."data" ->> 'valid_until', 'date') then (r."data" ->> 'valid_until')::date >= current_date
      else false end)
        and ((v_row."tenant_id")::text, ('person')::text, (r."source_id")::text) in (select g.tenant, g.party_type, g.party_id from better_supabase.portal_parties() g))) then
      raise exception 'not allowed to withdraw this consent' using errcode = '42501', hint = 'CONSENT_FORBIDDEN';
    end if;
    raise exception 'no such consent' using errcode = 'P0002', hint = 'CONSENT_NOT_FOUND';
  end if;
  if v_row."status" = 'withdrawn' then
    raise exception 'the consent is already withdrawn' using errcode = '22023', hint = 'CONSENT_ALREADY_WITHDRAWN';
  end if;
  if v_row."status" <> 'granted' then
    raise exception 'only a granted consent can be withdrawn' using errcode = '22023', hint = 'CONSENT_INVALID';
  end if;
  if length(v_reason) > 1000 then
    raise exception 'a reason is at most 1000 characters' using errcode = '22023', hint = 'CONSENT_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_consent_withdraw"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  update "better_supabase"."consents" x set
    "status" = 'withdrawn',
    "withdrawn_at" = now(),
    "withdrawn_reason" = v_reason
  where x."id" = v_row."id"
  returning * into v_row;
  select * into v_purpose from "better_supabase"."consent_purposes" x where x."id" = v_row."purpose_id";
  perform "better_supabase".emit_event('consent.withdrawn', jsonb_build_object('organizationId', v_row."tenant_id", 'consentId', v_row."id", 'purposeId', v_row."purpose_id", 'purposeKey', v_purpose."key", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status", 'givenBy', v_row."given_by"), 'consents/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/consents');
  perform better_supabase.audit_event(
    event_type => 'consent.withdrawn',
    category => 'data',
    target_type => 'consent',
    record_id => v_row."id"::text,
    target_label => v_purpose."title",
    summary => 'withdrew a consent',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'consentId', v_row."id", 'purposeId', v_row."purpose_id", 'purposeKey', v_purpose."key", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status", 'givenBy', v_row."given_by")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_consent_withdraw"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'purposeId', v_row."purpose_id", 'purposeKey', v_purpose."key", 'purposeTitle', v_purpose."title", 'purposeVersion', v_purpose."version", 'legalBasis', v_purpose."legal_basis", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'givenBy', v_row."given_by", 'givenByContactId', v_row."given_by_contact_id", 'givenByUserId', v_row."grantor_id", 'status', v_row."status", 'scope', coalesce(v_row."scope", '{}'::jsonb), 'grantedAt', v_row."granted_at", 'validUntil', v_row."expires_at", 'withdrawnAt', v_row."withdrawn_at", 'withdrawnReason', v_row."withdrawn_reason", 'signatureId', v_row."signature_id", 'submissionId', v_row."submission_id", 'attachmentId', v_row."attachment_id", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'active', (v_row."status" = 'granted' and (v_row."expires_at" is null or v_row."expires_at" > now())));
end;
$function$;

ALTER TABLE "better_supabase"."ai_chat_participants"
  ADD CONSTRAINT "ai_chat_participants_customer_id_fkey" FOREIGN KEY (customer_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."application_scorecards"
  ADD CONSTRAINT "application_scorecards_application_id_stage_id_reviewer_id_key" UNIQUE NULLS NOT DISTINCT (application_id, stage_id, reviewer_id);

ALTER TABLE "better_supabase"."appraisals"
  ADD CONSTRAINT "appraisals_cycle_id_appraisee_id_key" UNIQUE (cycle_id, appraisee_id);

ALTER TABLE "better_supabase"."enrollment_steps"
  ADD CONSTRAINT "enrollment_steps_assignee_id_fkey" FOREIGN KEY (assignee_id) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."passes"
  ADD CONSTRAINT "passes_holder_id_fkey" FOREIGN KEY (holder_id) REFERENCES auth.users(id) ON DELETE SET NULL;

REVOKE ALL ON FUNCTION "api"."request_shift_swap"(uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."request_shift_swap"(uuid, uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."request_shift_swap"(uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."request_shift_swap"(uuid, uuid, text) TO "authenticated", "service_role";
