SET local check_function_bodies = off;

DROP POLICY "comments_insert" ON "better_supabase"."comments";

DROP POLICY "comments_update" ON "better_supabase"."comments";

DROP POLICY "inbox_team_members_staff_read" ON "better_supabase"."inbox_team_members";

DROP POLICY "bs_notification_recipients_update" ON "better_supabase"."notification_recipients";

DROP POLICY "organization_settings_delete" ON "better_supabase"."organization_settings";

DROP POLICY "organization_settings_insert" ON "better_supabase"."organization_settings";

DROP POLICY "organization_settings_update" ON "better_supabase"."organization_settings";

DROP POLICY "platform_settings_delete" ON "better_supabase"."platform_settings";

DROP POLICY "platform_settings_insert" ON "better_supabase"."platform_settings";

DROP POLICY "platform_settings_update" ON "better_supabase"."platform_settings";

DROP POLICY "bs_profiles_update" ON "better_supabase"."profiles";

DROP POLICY "push_devices_own_delete" ON "better_supabase"."push_devices";

DROP POLICY "bs_inbox_broadcast" ON "realtime"."messages";

DROP POLICY "bs_ai_files_delete" ON "storage"."objects";

DROP POLICY "bs_ai_files_insert" ON "storage"."objects";

DROP POLICY "bs_inbox_files_write" ON "storage"."objects";

ALTER TABLE "better_supabase"."conversations"
  DROP CONSTRAINT "conversations_team_id_fkey";

ALTER TABLE "better_supabase"."inbox_team_members"
  DROP CONSTRAINT "inbox_team_members_team_id_fkey";

ALTER TABLE "better_supabase"."inbox_team_members"
  DROP CONSTRAINT "inbox_team_members_user_id_fkey";

DROP TABLE "better_supabase"."inbox_team_members";

DROP TABLE "better_supabase"."inbox_teams";

CREATE TABLE "better_supabase"."team_members" (
  "team_id"    uuid                     NOT NULL,
  "user_id"    uuid                     NOT NULL,
  "tenant_id"  uuid                     NOT NULL,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "team_members_pkey" PRIMARY KEY (team_id, user_id)
);

ALTER TABLE "better_supabase"."team_members"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."teams" (
  "id"          uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"   uuid                     NOT NULL,
  "name"        text                     NOT NULL,
  "slug"        text                     NOT NULL,
  "description" text,
  "status"      text                     NOT NULL DEFAULT 'active'::text,
  "created_by"  uuid,
  "created_at"  timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"  timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "teams_name_check" CHECK (((length(name) >= 1) AND (length(name) <= 200))),
  CONSTRAINT "teams_pkey" PRIMARY KEY (id),
  CONSTRAINT "teams_slug_check" CHECK ((slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'::text)),
  CONSTRAINT "teams_status_check" CHECK ((status = ANY (ARRAY['active'::text, 'archived'::text]))),
  CONSTRAINT "teams_tenant_id_slug_key" UNIQUE (tenant_id, slug)
);

ALTER TABLE "better_supabase"."teams"
  ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION api.actor_may_write()
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."actor_may_write"() $function$;

CREATE OR REPLACE FUNCTION api.raise_actor_readonly()
  RETURNS void
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."raise_actor_readonly"() $function$;

CREATE OR REPLACE FUNCTION better_supabase.accept_invitation (
  token text
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  me uuid := auth.uid();
  invite "better_supabase"."invitations";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if me is null then
    raise exception 'Sign in to accept an invitation' using errcode = '42501', hint = 'INVITATION_SIGN_IN';
  end if;
  select * into invite
  from "better_supabase"."invitations" i
  where i."token_hash" = encode(extensions.digest(token, 'sha256'), 'hex')
  for update;
  if invite."id" is null then
    raise exception 'The invitation is invalid or has expired' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if not (invite."accepted_at" is null and invite."declined_at" is null and invite."revoked_at" is null) then
    raise exception 'The invitation is invalid or has expired' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if invite."expires_at" < now() then
    raise exception 'The invitation has expired; ask for a new one' using errcode = 'P0002', hint = 'INVITATION_EXPIRED';
  end if;
  if lower(invite."email") <> lower(coalesce(auth.jwt() ->> 'email', '')) then
    raise exception 'The invitation is for another email address' using errcode = '42501', hint = 'INVITATION_EMAIL_MISMATCH';
  end if;
  -- The email claim alone does not prove the address: an unconfirmed sign-up carries it too.
  if not exists (
    select 1 from auth.users u
    where u.id = me and u.email_confirmed_at is not null and lower(u.email) = lower(invite."email")
  ) then
    raise exception 'Confirm your email address before accepting the invitation' using errcode = '42501', hint = 'INVITATION_EMAIL_UNCONFIRMED';
  end if;
  if invite."invited_by" = me then
    raise exception 'You cannot accept your own invitation' using errcode = '42501', hint = 'INVITATION_SELF';
  end if;
  if better_supabase.tenant_disabled(invite."organization_id") or not exists (select 1 from "public"."organizations" o where o."id" = invite."organization_id") then
    raise exception 'The invitation is invalid or has expired' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if exists (select 1 from "public"."memberships" m where m."organization_id" = invite."organization_id" and m."user_id" = me) then
    raise exception 'You are already a member' using errcode = '23505', hint = 'INVITATION_ALREADY_MEMBER';
  end if;
    if invite."invited_by" is not null
      and better_supabase.can_user(invite."invited_by", 'organization', invite."organization_id", 'members.invite') is false then
      raise exception 'The person who invited you can no longer invite members' using errcode = '42501', hint = 'INVITATION_INVITER_REVOKED';
    end if;
    if invite."invited_by" is not null
      and not better_supabase.can_assign_as(invite."invited_by", invite."organization_id", invite."role"::text) then
      raise exception 'The person who invited you can no longer assign that role' using errcode = '42501', hint = 'INVITATION_INVITER_REVOKED';
    end if;
  insert into "public"."memberships" ("organization_id", "user_id", "role")
  values (invite."organization_id", me, invite."role");
  update "better_supabase"."invitations"
  set "accepted_at" = now(), "accepted_by" = me
  where "id" = invite."id";
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_invitation_accept"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using invite."id", me;
    end if;
  end;
  perform better_supabase.audit_event(
    event_type => 'invitation.accepted',
    category => 'membership',
    target_type => 'invitation',
    record_id => invite."id"::text,
    tenant => (invite."organization_id")::uuid,
    metadata => jsonb_build_object('invitationId', invite."id", 'organizationId', invite."organization_id"::text, 'email', invite."email", 'role', invite."role")
  );
  perform better_supabase.audit_event(
    event_type => 'organization.member_added',
    category => 'membership',
    target_type => 'user',
    record_id => me::text,
    tenant => (invite."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', invite."organization_id"::text, 'userId', me, 'role', invite."role")
  );
  return invite."organization_id";
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.accept_invitation_by_id (
  invitation_id uuid
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  me uuid := auth.uid();
  invite "better_supabase"."invitations";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if me is null then
    raise exception 'Sign in to accept an invitation' using errcode = '42501', hint = 'INVITATION_SIGN_IN';
  end if;
  select * into invite
  from "better_supabase"."invitations" i
  where i."id" = invitation_id
  for update;
  if invite."id" is null then
    raise exception 'The invitation is invalid or has expired' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if not (invite."accepted_at" is null and invite."declined_at" is null and invite."revoked_at" is null) then
    raise exception 'The invitation is invalid or has expired' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if invite."expires_at" < now() then
    raise exception 'The invitation has expired; ask for a new one' using errcode = 'P0002', hint = 'INVITATION_EXPIRED';
  end if;
  if lower(invite."email") <> lower(coalesce(auth.jwt() ->> 'email', '')) then
    raise exception 'The invitation is for another email address' using errcode = '42501', hint = 'INVITATION_EMAIL_MISMATCH';
  end if;
  -- The email claim alone does not prove the address: an unconfirmed sign-up carries it too.
  if not exists (
    select 1 from auth.users u
    where u.id = me and u.email_confirmed_at is not null and lower(u.email) = lower(invite."email")
  ) then
    raise exception 'Confirm your email address before accepting the invitation' using errcode = '42501', hint = 'INVITATION_EMAIL_UNCONFIRMED';
  end if;
  if invite."invited_by" = me then
    raise exception 'You cannot accept your own invitation' using errcode = '42501', hint = 'INVITATION_SELF';
  end if;
  if better_supabase.tenant_disabled(invite."organization_id") or not exists (select 1 from "public"."organizations" o where o."id" = invite."organization_id") then
    raise exception 'The invitation is invalid or has expired' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if exists (select 1 from "public"."memberships" m where m."organization_id" = invite."organization_id" and m."user_id" = me) then
    raise exception 'You are already a member' using errcode = '23505', hint = 'INVITATION_ALREADY_MEMBER';
  end if;
    if invite."invited_by" is not null
      and better_supabase.can_user(invite."invited_by", 'organization', invite."organization_id", 'members.invite') is false then
      raise exception 'The person who invited you can no longer invite members' using errcode = '42501', hint = 'INVITATION_INVITER_REVOKED';
    end if;
    if invite."invited_by" is not null
      and not better_supabase.can_assign_as(invite."invited_by", invite."organization_id", invite."role"::text) then
      raise exception 'The person who invited you can no longer assign that role' using errcode = '42501', hint = 'INVITATION_INVITER_REVOKED';
    end if;
  insert into "public"."memberships" ("organization_id", "user_id", "role")
  values (invite."organization_id", me, invite."role");
  update "better_supabase"."invitations"
  set "accepted_at" = now(), "accepted_by" = me
  where "id" = invite."id";
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_invitation_accept"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using invite."id", me;
    end if;
  end;
  perform better_supabase.audit_event(
    event_type => 'invitation.accepted',
    category => 'membership',
    target_type => 'invitation',
    record_id => invite."id"::text,
    tenant => (invite."organization_id")::uuid,
    metadata => jsonb_build_object('invitationId', invite."id", 'organizationId', invite."organization_id"::text, 'email', invite."email", 'role', invite."role")
  );
  perform better_supabase.audit_event(
    event_type => 'organization.member_added',
    category => 'membership',
    target_type => 'user',
    record_id => me::text,
    tenant => (invite."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', invite."organization_id"::text, 'userId', me, 'role', invite."role")
  );
  return invite."organization_id";
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.actor_may_write()
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select case
    when auth.jwt() is null then true
    when coalesce(auth.jwt() -> 'act' ->> 'read_only', '') = 'false' then true
    when auth.jwt() -> 'act' ->> 'kind' in ('support', 'impersonation') then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.add_team_member (
  team   uuid,
  member uuid
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
  select "tenant_id" into v_tenant from "better_supabase"."teams" where "id" = add_team_member.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  if not exists (
    select 1 from "public"."memberships" m
    where m."organization_id" = v_tenant
      and m."user_id" = add_team_member.member
  ) then
    raise exception 'user is not a member of the tenant' using errcode = '22023', hint = 'TEAM_MEMBER_INVALID';
  end if;
  insert into "better_supabase"."team_members" ("team_id", "user_id", "tenant_id")
  values (add_team_member.team, add_team_member.member, v_tenant)
  on conflict do nothing;
  perform better_supabase.audit_event(
    event_type => 'team_member.added',
    category => 'membership',
    target_type => 'team',
    record_id => (add_team_member.team)::text,
    tenant => (v_tenant)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'id', add_team_member.team, 'userId', add_team_member.member)
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.answer_ai_pending_input (
  id     uuid,
  answer jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."ai_pending_inputs";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."ai_pending_inputs" x where x."id" = answer_ai_pending_input.id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = (select auth.uid())) then
    raise exception 'No question %', answer_ai_pending_input.id using errcode = 'P0002', hint = 'AI_INPUT_NOT_FOUND';
  end if;
  if v_row."answered_at" is not null then
    raise exception 'Question % was answered', answer_ai_pending_input.id using errcode = 'P0001', hint = 'AI_INPUT_ANSWERED';
  end if;
  update "better_supabase"."ai_pending_inputs" x set "answer" = coalesce(answer_ai_pending_input.answer, 'null'::jsonb), "answered_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase"."ai_chat_notify"(v_row."chat_id", null, 'input.answered', jsonb_build_object('inputId', v_row."id"), false);
  return jsonb_build_object('id', v_row."id", 'chat_id', v_row."chat_id", 'run_id', v_row."run_id", 'tool_call_id', v_row."tool_call_id", 'question', v_row."question", 'schema', v_row."schema", 'answer', v_row."answer", 'answered_at', v_row."answered_at", 'created_at', v_row."created_at");
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
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_chat."owner_id" = (select auth.uid())) then
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
  insert into "better_supabase"."ai_messages" ("chat_id", "id", "parent_id", "owner_id", "role", "parts", "metadata")
  values (
    v_chat."id", v_id, v_parent, v_chat."owner_id", 'user', append_ai_user_message.message -> 'parts',
    case when jsonb_typeof(append_ai_user_message.message -> 'metadata') = 'object' then append_ai_user_message.message -> 'metadata' else '{}'::jsonb end
  );
  update "better_supabase"."ai_chats" x set "current_leaf_id" = v_id, "last_message_at" = clock_timestamp(), "updated_at" = now() where x."id" = v_chat."id";
  perform "better_supabase"."ai_chat_notify"(v_chat."id", v_chat."owner_id", 'message.saved', jsonb_build_object('messageId', v_id), not v_chat."is_temporary");
  return jsonb_build_object('message_id', v_id, 'parent_id', v_parent, 'created', true);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.archive_team (
  team uuid
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
  select "tenant_id" into v_tenant from "better_supabase"."teams" where "id" = archive_team.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  update "better_supabase"."teams" set "status" = 'archived', "updated_at" = now() where "id" = archive_team.team;
  perform better_supabase.audit_event(
    event_type => 'team.archived',
    category => 'membership',
    target_type => 'team',
    record_id => (archive_team.team)::text,
    tenant => (v_tenant)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'id', archive_team.team)
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.assign_conversation (
  conversation uuid,
  assignee     uuid,
  team         uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_conv "better_supabase"."conversations"%rowtype;
  v_before uuid;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_conv from "better_supabase"."conversations" where "id" = assign_conversation.conversation for update;
  if not found then
    raise exception 'conversation not found' using errcode = 'P0002', hint = 'CONVERSATION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_conv."tenant_id", 'inbox.assign'), false) or (assignee = (select auth.uid()) and coalesce(better_supabase.can('tenant', v_conv."tenant_id", 'inbox.reply'), false))) then
    raise exception 'not allowed to assign this conversation' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  if assignee is not null and not coalesce(better_supabase.can_user(assignee, 'tenant', v_conv."tenant_id", 'inbox.read'), false) then
    raise exception 'the assignee cannot read this inbox' using errcode = '22023', hint = 'INBOX_ASSIGNEE_INVALID';
  end if;
  v_before := v_conv."assignee_id";
  update "better_supabase"."conversations" set
    "assignee_id" = assign_conversation.assignee,
    "team_id" = coalesce(assign_conversation.team, "team_id")
  where "id" = v_conv."id"
  returning * into v_conv;
  if v_before is distinct from assignee then
    insert into "better_supabase"."conversation_events" ("tenant_id", "conversation_id", "type", "actor_id", "data")
  values (v_conv."tenant_id", v_conv."id", 'assigned', (select auth.uid()), jsonb_build_object('from', v_before, 'to', assign_conversation.assignee));
    null;
    if assignee is not null then
      insert into "better_supabase"."conversation_participants" ("conversation_id", "user_id") values (v_conv."id", assignee)
      on conflict do nothing;
    end if;
    if assignee is not null and assignee is distinct from (select auth.uid()) then
  v_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
  perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'inbox.assigned',
        'tenant', v_conv."tenant_id",
        'actor', (select auth.uid()),
        'subject_type', 'conversation',
        'subject_id', v_conv."id"::text,
        'summary', v_conv."subject",
        'recipients', to_jsonb(array[assignee]),
        'key', 'inbox.assigned:' || v_conv."id"::text || ':' || assignee::text || ':' || extract(epoch from now())::text,
        'data', jsonb_build_object('conversationId', v_conv."id")
      ));
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
      null;
    end if;
  end if;
  return "better_supabase"."inbox_conversation_json"(v_conv."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.audit_event (
  event_type           text,
  category             text  DEFAULT NULL::text,
  outcome              text  DEFAULT 'success'::text,
  source               text  DEFAULT NULL::text,
  target_type          text  DEFAULT NULL::text,
  record_id            text  DEFAULT NULL::text,
  tenant               uuid  DEFAULT NULL::uuid,
  metadata             jsonb DEFAULT '{}'::jsonb,
  idempotency_key      text  DEFAULT NULL::text,
  restricted           jsonb DEFAULT NULL::jsonb,
  actor_id             uuid  DEFAULT NULL::uuid,
  summary              text  DEFAULT NULL::text,
  target_label         text  DEFAULT NULL::text,
  correlation_id       text  DEFAULT NULL::text,
  actor_kind           text  DEFAULT NULL::text,
  actor_label          text  DEFAULT NULL::text,
  ip                   inet  DEFAULT NULL::inet,
  user_agent           text  DEFAULT NULL::text,
  session_id           text  DEFAULT NULL::text,
  request_id           text  DEFAULT NULL::text,
  scope                text  DEFAULT NULL::text,
  support_session      uuid  DEFAULT NULL::uuid,
  impersonated_by      uuid  DEFAULT NULL::uuid,
  impersonation_reason text  DEFAULT NULL::text
)
  RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  existing text;
  entry_id "better_supabase"."audit_events"."id"%type;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if restricted is not null or ip is not null or user_agent is not null or session_id is not null then
    raise exception 'audit_event got restricted details, and the audit module has no restricted table'
      using errcode = '22023', hint = 'Set sql.modules.audit.options.restricted to true.';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    actor_id := auth.uid();
    actor_kind := null;
    actor_label := null;
    ip := null;
    user_agent := null;
    session_id := null;
    request_id := null;
    scope := null;
    if (select auth.jwt()) -> 'act' is not null or impersonated_by is distinct from auth.uid() then
      support_session := null;
      impersonated_by := null;
      impersonation_reason := null;
    end if;
  elsif actor_id is null then
    actor_id := auth.uid();
  end if;
  if idempotency_key is not null then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('better_supabase.audit_event'), pg_catalog.hashtext(coalesce(tenant::text, '') || ':' || idempotency_key));
    select l."id"::text into existing
    from "better_supabase"."audit_events" l
    where l."idempotency_key" = audit_event.idempotency_key
      and l."organization_id" is not distinct from audit_event.tenant
    limit 1;
    if existing is not null then
      return existing;
    end if;
  end if;
  insert into "better_supabase"."audit_events" ("table_name", "record_id", "op", "actor_id", "actor_role", "organization_id", "impersonated_by", "impersonation_reason", "support_session_id", "event_type", "category", "outcome", "source", "target_type", "metadata", "idempotency_key", "actor_kind", "actor_label", "tenant_label", "target_label", "summary", "request_id", "correlation_id", "scope")
  values (
    null,
    record_id,
    'event',
    actor_id,
    coalesce(auth.jwt() ->> 'role', current_user),
    tenant,
    coalesce(audit_event.impersonated_by, case when auth.jwt() -> 'act' ->> 'sub' ~ '^[0-9a-f-]{36}$' then (auth.jwt() -> 'act' ->> 'sub')::uuid end),
    coalesce(audit_event.impersonation_reason, auth.jwt() -> 'act' ->> 'reason'),
    coalesce(audit_event.support_session, case when auth.jwt() -> 'act' ->> 'session_id' ~ '^[0-9a-f-]{36}$' then (auth.jwt() -> 'act' ->> 'session_id')::uuid end),
    event_type,
    coalesce(category, 'system'),
    coalesce(outcome, 'success'),
    coalesce(source, 'app'),
    target_type,
    coalesce(metadata, '{}'),
    idempotency_key,
    coalesce(actor_kind, case
      when coalesce(auth.jwt() ->> 'role', '') = 'service_role' then 'service'
      when auth.jwt() -> 'act' ->> 'kind' = 'support' then 'support'
      when auth.jwt() -> 'act' is not null then 'impersonation'
      when auth.jwt() ->> 'client_id' is not null then 'oauth-client'
      when auth.uid() is not null then 'user'
      else 'system'
    end),
    coalesce(actor_label, coalesce(auth.jwt() -> 'user_metadata' ->> 'full_name', auth.jwt() ->> 'email')),
    (select o."name"::text from "public"."organizations" o where o."id" = tenant),
    target_label,
    summary,
    coalesce(better_supabase.request_id_or_null(request_id), coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.request_id', true)), better_supabase.request_id_or_null(better_supabase.request_header('x-request-id')))),
    coalesce(better_supabase.request_id_or_null(correlation_id), coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.correlation_id', true)), better_supabase.request_id_or_null(better_supabase.request_header('x-correlation-id')))),
    coalesce(audit_event.scope, case when tenant is null then 'platform' else 'tenant' end)
  )
  returning "id" into entry_id;
  return entry_id::text;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.check_connector_fingerprint (
  server_id   uuid,
  fingerprint text,
  tools       jsonb DEFAULT '{}'::jsonb
)
  RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_server "better_supabase"."connector_servers"%rowtype;
  v_status text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_server from "better_supabase"."connector_servers" x where x."id" = check_connector_fingerprint.server_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_server."organization_id", 'ai.create'), false)) then
    raise exception 'connector % not found', check_connector_fingerprint.server_id using errcode = 'P0002', hint = 'CONNECTOR_NOT_FOUND';
  end if;
  select p."status" into v_status from "better_supabase"."connector_tool_fingerprints" p
  where p."server_id" = v_server."id" and p."fingerprint" = check_connector_fingerprint.fingerprint;
  if found then
    return v_status;
  end if;
  v_status := case when exists (select 1 from "better_supabase"."connector_tool_fingerprints" p where p."server_id" = v_server."id") then 'pending' else 'approved' end;
  insert into "better_supabase"."connector_tool_fingerprints" ("server_id", "fingerprint", "tools", "status", "approved_at")
  values (v_server."id", check_connector_fingerprint.fingerprint, coalesce(check_connector_fingerprint.tools, '{}'), v_status,
    case when v_status = 'approved' then now() end)
  on conflict do nothing;
  return v_status;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.complete_onboarding_step (
  checklist text,
  step      text,
  tenant    uuid DEFAULT NULL::uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_scope text;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  v_scope := (select s.scope from (values ('getting-started', 'customer', 'organization'), ('getting-started', 'invite', 'organization'), ('getting-started', 'api-key', 'organization'), ('getting-started', 'plan', 'organization')) as s(checklist, step, scope) where s.checklist = complete_onboarding_step.checklist and (complete_onboarding_step.step is null or s.step = complete_onboarding_step.step) limit 1);
  if v_scope is null then
    raise exception 'Unknown onboarding step %.%', complete_onboarding_step.checklist, coalesce(complete_onboarding_step.step, '*') using errcode = '22023', hint = 'ONBOARDING_STEP_UNKNOWN';
  end if;
  if v_scope = 'organization' then
    if complete_onboarding_step.tenant is null then
      raise exception 'Checklist % belongs to an organization', complete_onboarding_step.checklist using errcode = '22023', hint = 'ONBOARDING_SCOPE';
    end if;
  elsif complete_onboarding_step.tenant is not null then
    raise exception 'Checklist % belongs to a user', complete_onboarding_step.checklist using errcode = '22023', hint = 'ONBOARDING_SCOPE';
  elsif auth.uid() is null then
    raise exception 'Sign in first' using errcode = '42501', hint = 'ONBOARDING_FORBIDDEN';
  end if;
  if v_scope = 'organization' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', complete_onboarding_step.tenant, 'onboarding.complete'), false)) then
    raise exception 'You may not complete this organization''s onboarding' using errcode = '42501', hint = 'ONBOARDING_FORBIDDEN';
  end if;
  insert into "better_supabase"."onboarding_progress" ("checklist", "step", "user_id", "organization_id", "completed_by")
  values (
    complete_onboarding_step.checklist,
    complete_onboarding_step.step,
    case when v_scope = 'user' then auth.uid() end,
    case when v_scope = 'organization' then complete_onboarding_step.tenant end,
    auth.uid()
  )
  on conflict do nothing;
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.confirm_ai_file (
  file_id uuid,
  sha256  text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."ai_files"%rowtype;
  v_size bigint;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."ai_files" x where x."id" = confirm_ai_file.file_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = auth.uid()) then
    raise exception 'file % not found', file_id using errcode = 'P0002', hint = 'AI_FILE_NOT_FOUND';
  end if;
  if v_row."status" <> 'pending' then
    return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'chat_id', v_row."chat_id", 'project_id', v_row."project_id", 'bucket', v_row."bucket", 'path', v_row."path", 'media_type', v_row."media_type", 'filename', v_row."filename", 'byte_size', v_row."byte_size", 'sha256', v_row."sha256", 'status', v_row."status", 'source', v_row."source", 'created_at', v_row."created_at", 'uploaded_at', v_row."uploaded_at", 'expires_at', v_row."expires_at");
  end if;
  select (o.metadata ->> 'size')::bigint into v_size
  from storage.objects o where o.bucket_id = v_row."bucket" and o.name = v_row."path";
  if not found then
    raise exception 'file % has no uploaded object yet', file_id using errcode = 'P0001', hint = 'AI_FILE_NOT_UPLOADED';
  end if;
  update "better_supabase"."ai_files" x set
    "status" = 'ready',
    "uploaded_at" = now(),
    "byte_size" = coalesce(v_size, x."byte_size"),
    "sha256" = coalesce(lower(confirm_ai_file.sha256), x."sha256")
  where x."id" = v_row."id"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'chat_id', v_row."chat_id", 'project_id', v_row."project_id", 'bucket', v_row."bucket", 'path', v_row."path", 'media_type', v_row."media_type", 'filename', v_row."filename", 'byte_size', v_row."byte_size", 'sha256', v_row."sha256", 'status', v_row."status", 'source', v_row."source", 'created_at', v_row."created_at", 'uploaded_at', v_row."uploaded_at", 'expires_at', v_row."expires_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_ai_chat (
  tenant uuid,
  fields jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_fields jsonb := coalesce(create_ai_chat.fields, '{}'::jsonb);
  v_owner uuid := auth.uid();
  v_row "better_supabase"."ai_chats";
  v_id uuid;
  v_project uuid := (v_fields ->> 'project_id')::uuid;
  v_temporary boolean := coalesce((v_fields ->> 'is_temporary')::boolean, false);
  v_visibility text := coalesce(v_fields ->> 'visibility', 'private');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    v_owner := coalesce((v_fields ->> 'owner_id')::uuid, v_owner);
  elsif not coalesce(better_supabase.can('tenant', create_ai_chat.tenant, 'ai_chat.create'), false) then
    raise exception 'You may not start chats here' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  if v_owner is null then
    raise exception 'Sign in first' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  if v_visibility = 'organization' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_ai_chat.tenant, 'ai_chat.share'), false)) then
    raise exception 'You may not share chats here' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  v_id := coalesce((v_fields ->> 'id')::uuid, gen_random_uuid());
  select * into v_row from "better_supabase"."ai_chats" x where x."id" = v_id;
  if found then
    if v_row."owner_id" <> v_owner then
      raise exception 'Chat % exists', v_id using errcode = '23505', hint = 'AI_CHAT_EXISTS';
    end if;
    return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'project_id', v_row."project_id", 'agent_id', v_row."agent_id", 'title', v_row."title", 'model', v_row."model", 'visibility', v_row."visibility", 'pinned', v_row."pinned", 'archived_at', v_row."archived_at", 'is_temporary', v_row."is_temporary", 'expires_at', v_row."expires_at", 'current_leaf_id', v_row."current_leaf_id", 'active_stream_id', v_row."active_stream_id", 'active_run_id', v_row."active_run_id", 'last_message_at', v_row."last_message_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
  end if;
  if v_project is not null and not exists (select 1 from "better_supabase"."ai_projects" pr where pr."id" = v_project and pr."owner_id" = v_owner and pr."organization_id" = create_ai_chat.tenant) then
    raise exception 'No project %', v_project using errcode = 'P0002', hint = 'AI_PROJECT_NOT_FOUND';
  end if;
  insert into "better_supabase"."ai_chats" ("id", "organization_id", "owner_id", "project_id", "agent_id", "title", "model", "visibility", "is_temporary", "expires_at")
  values (
    v_id, create_ai_chat.tenant, v_owner, v_project, v_fields ->> 'agent_id',
    coalesce(v_fields ->> 'title', ''), v_fields ->> 'model', v_visibility, v_temporary,
    case when v_temporary then now() + interval '1 day' end
  )
  returning * into v_row;
  if not v_temporary then
    perform "better_supabase"."ai_chat_notify"(v_id, v_owner, 'chat.created', '{}'::jsonb, true);
  end if;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'project_id', v_row."project_id", 'agent_id', v_row."agent_id", 'title', v_row."title", 'model', v_row."model", 'visibility', v_row."visibility", 'pinned', v_row."pinned", 'archived_at', v_row."archived_at", 'is_temporary', v_row."is_temporary", 'expires_at', v_row."expires_at", 'current_leaf_id', v_row."current_leaf_id", 'active_stream_id', v_row."active_stream_id", 'active_run_id', v_row."active_run_id", 'last_message_at', v_row."last_message_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_ai_document (
  tenant       uuid,
  kind         text,
  title        text,
  content      text DEFAULT NULL::text,
  chat_id      uuid DEFAULT NULL::uuid,
  message_id   text DEFAULT NULL::text,
  owner        uuid DEFAULT NULL::uuid,
  storage_path text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_owner uuid := case when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then create_ai_document.owner else auth.uid() end;
  v_row "better_supabase"."ai_documents"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_owner is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_ai_document.tenant, 'ai.create'), false)) then
    raise exception 'you may not create documents here' using errcode = '42501', hint = 'AI_DOCUMENT_FORBIDDEN';
  end if;
  insert into "better_supabase"."ai_documents" ("organization_id", "owner_id", "chat_id", "kind", "title")
  values (create_ai_document.tenant, v_owner, create_ai_document.chat_id, create_ai_document.kind, create_ai_document.title)
  returning * into v_row;
  insert into "better_supabase"."ai_document_versions" ("document_id", "version", "content", "storage_path", "created_by_message_id", "created_by")
  values (v_row."id", 1, create_ai_document.content, create_ai_document.storage_path, create_ai_document.message_id, v_owner);
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'chat_id', v_row."chat_id", 'kind', v_row."kind", 'title', v_row."title", 'current_version', v_row."current_version", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_api_key (
  name        text,
  public_id   text,
  secret_hash text,
  tenant      uuid                     DEFAULT NULL::uuid,
  personal    boolean                  DEFAULT false,
  scopes      text[]                   DEFAULT '{}'::text[],
  expires_at  timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  rate_limit  integer                  DEFAULT NULL::integer,
  prefix      text                     DEFAULT 'bs'::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  owner uuid := case when personal then auth.uid() end;
  created "better_supabase"."api_keys";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if personal and owner is null then
    raise exception 'Sign in to create a personal API key' using errcode = '42501', hint = 'API_KEY_SIGN_IN';
  end if;
  if not personal and tenant is null then
    raise exception 'A tenant API key needs a tenant' using errcode = '22023', hint = 'API_KEY_TENANT_REQUIRED';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    if not personal and not coalesce(better_supabase.can('tenant', tenant, 'api_keys.manage'), false) then
      raise exception 'Not allowed to manage API keys in this tenant' using errcode = '42501', hint = 'API_KEY_FORBIDDEN';
    end if;
    if personal and tenant is not null and not coalesce(better_supabase.can('tenant', tenant, 'api_keys.own'), false) then
      raise exception 'Not allowed to create API keys in this tenant' using errcode = '42501', hint = 'API_KEY_FORBIDDEN';
    end if;
    if personal and tenant is null and exists (
      select 1 from better_supabase.member_organization_ids() as m(id)
      where m.id not in (select better_supabase.tenant_ids_with('api_keys.own'))
    ) then
      raise exception 'Not allowed to create API keys for every tenant' using errcode = '42501', hint = 'API_KEY_FORBIDDEN';
    end if;
  end if;
  if expires_at is not null and expires_at <= now() then
    raise exception 'expires_at is in the past' using errcode = '22023', hint = 'API_KEY_EXPIRED';
  end if;
  insert into "better_supabase"."api_keys" ("organization_id", "user_id", "name", "prefix", "public_id", "secret_hash", "scopes", "rate_limit", "expires_at")
  values (tenant, owner, create_api_key.name, create_api_key.prefix, create_api_key.public_id, create_api_key.secret_hash, coalesce(create_api_key.scopes, '{}'), create_api_key.rate_limit, create_api_key.expires_at)
  returning * into created;
  perform better_supabase.audit_event(
    event_type => 'api_key.created',
    category => 'security',
    target_type => 'api_key',
    record_id => created."id"::text,
    target_label => created."name",
    tenant => (created."organization_id")::uuid,
    metadata => jsonb_build_object('keyId', created."id", 'organizationId', created."organization_id"::text, 'userId', created."user_id", 'name', created."name", 'publicId', created."public_id")
  );
  return jsonb_build_object(
    'id', created."id",
    'organization_id', created."organization_id",
    'user_id', created."user_id",
    'name', created."name",
    'prefix', created."prefix",
    'public_id', created."public_id",
    'scopes', to_jsonb(created."scopes"),
    'rate_limit', created."rate_limit",
    'expires_at', created."expires_at",
    'last_used_at', created."last_used_at",
    'revoked_at', created."revoked_at",
    'rotated_from', created."rotated_from",
    'created_by', created."created_by",
    'created_at', created."created_at",
    'state', case
      when created."revoked_at" is not null and created."revoked_at" <= now() then 'revoked'
      when created."expires_at" is not null and created."expires_at" <= now() then 'expired'
      when created."revoked_at" is not null then 'grace'
      else 'active'
    end,
    'successor_id', (select s."id" from "better_supabase"."api_keys" s where s."rotated_from" = created."id" order by s."created_at" desc limit 1)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_inbox (
  tenant   uuid,
  name     text,
  channel  text  DEFAULT 'in_app'::text,
  settings jsonb DEFAULT '{}'::jsonb,
  bot_mode text  DEFAULT 'human'::text,
  address  text  DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."inboxes"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_inbox.tenant, 'inbox.manage'), false)) then
    raise exception 'not allowed to manage inboxes' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  insert into "better_supabase"."inboxes" ("tenant_id", "name", "channel", "settings", "bot_mode", "channel_address")
  values (create_inbox.tenant, create_inbox.name, coalesce(create_inbox.channel, 'in_app'), coalesce(create_inbox.settings, '{}'::jsonb), coalesce(create_inbox.bot_mode, 'human'), create_inbox.address)
  returning * into v_row;
  return to_jsonb(v_row);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_inbox_team (
  tenant uuid,
  name   text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_inbox_team.tenant, 'inbox.manage'), false)) then
    raise exception 'not allowed to manage inboxes' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  return "better_supabase"."create_team"(create_inbox_team.tenant, create_inbox_team.name, null);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_knowledge_document (
  tenant   uuid,
  title    text,
  scope    text  DEFAULT 'user'::text,
  scope_id uuid  DEFAULT NULL::uuid,
  file_id  uuid  DEFAULT NULL::uuid,
  source   text  DEFAULT NULL::text,
  metadata jsonb DEFAULT '{}'::jsonb,
  owner    uuid  DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_owner uuid := case when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then create_knowledge_document.owner else auth.uid() end;
  v_scope_id uuid := create_knowledge_document.scope_id;
  v_row "better_supabase"."knowledge_documents"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and (auth.uid() is null or not coalesce(better_supabase.can('tenant', create_knowledge_document.tenant, 'ai.create'), false)) then
    raise exception 'you may not add knowledge here' using errcode = '42501', hint = 'KNOWLEDGE_FORBIDDEN';
  end if;
  if create_knowledge_document.scope in ('organization', 'agent') and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_knowledge_document.tenant, 'ai.admin'), false)) then
    raise exception 'only admins add % knowledge', create_knowledge_document.scope using errcode = '42501', hint = 'KNOWLEDGE_FORBIDDEN';
  end if;
  if create_knowledge_document.scope = 'user' then
    v_scope_id := coalesce(v_scope_id, v_owner);
    if v_scope_id is null or v_scope_id is distinct from v_owner then
      raise exception 'user knowledge belongs to its owner' using errcode = '22023', hint = 'KNOWLEDGE_SCOPE';
    end if;
  end if;
  if create_knowledge_document.scope is null
    or create_knowledge_document.scope not in ('organization', 'agent', 'project', 'chat', 'user')
    or (create_knowledge_document.scope = 'organization') <> (v_scope_id is null) then
    raise exception '% knowledge needs %', create_knowledge_document.scope, case when create_knowledge_document.scope = 'organization' then 'no scope_id' else 'a scope_id' end using errcode = '22023', hint = 'KNOWLEDGE_SCOPE';
  end if;
  if create_knowledge_document.scope = 'chat' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_scope_id is not null and "better_supabase"."ai_chat_can_read"(v_scope_id))) then
    raise exception 'chat % not found', v_scope_id using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  if file_id is not null and not exists (
    select 1 from "better_supabase"."ai_files" x
    where x."id" = create_knowledge_document.file_id
      and x."organization_id" = create_knowledge_document.tenant
      and x."status" = 'ready'
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or x."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', create_knowledge_document.tenant, 'ai.admin'), false))
  ) then
    raise exception 'file % not found', file_id using errcode = 'P0002', hint = 'AI_FILE_NOT_FOUND';
  end if;
  insert into "better_supabase"."knowledge_documents" ("organization_id", "owner_id", "scope", "scope_id", "file_id", "title", "source", "metadata")
  values (create_knowledge_document.tenant, v_owner, create_knowledge_document.scope, v_scope_id, create_knowledge_document.file_id, create_knowledge_document.title, create_knowledge_document.source, coalesce(create_knowledge_document.metadata, '{}'))
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'scope', v_row."scope", 'scope_id', v_row."scope_id", 'file_id', v_row."file_id", 'title', v_row."title", 'source', v_row."source", 'metadata', v_row."metadata", 'status', v_row."status", 'error', v_row."error", 'chunk_count', v_row."chunk_count", 'embedding_model', v_row."embedding_model", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_organization (
  attrs jsonb
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
  owner uuid := case when service then nullif(attrs ->> 'owner_id', '')::uuid else auth.uid() end;
  organization uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if owner is null then
    raise exception 'An organization needs an owner' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  if better_supabase.user_disabled(owner) then
    raise exception 'The user is disabled' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  case "better_supabase"."organization_slug_problem"(attrs ->> 'slug', null)
    when 'invalid' then raise exception 'Invalid slug "%"', attrs ->> 'slug' using errcode = '23514', hint = 'ORGANIZATION_SLUG_INVALID';
    when 'reserved' then raise exception 'The slug "%" is reserved', attrs ->> 'slug' using errcode = '23514', hint = 'ORGANIZATION_SLUG_RESERVED';
    when 'taken' then raise exception 'The slug "%" is taken', attrs ->> 'slug' using errcode = '23505', hint = 'ORGANIZATION_SLUG_TAKEN';
    else null;
  end case;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_organization_create"(jsonb, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::jsonb, $2::uuid)', v_hook::oid::regproc)
        using attrs, owner;
    end if;
  end;
  insert into "public"."organizations" ("name", "slug")
  select r."name", r."slug"
  from jsonb_populate_record(null::"public"."organizations", attrs) r
  returning "id" into organization;
  insert into "public"."memberships" ("organization_id", "user_id", "role")
  values (organization, owner, 'owner');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_organization_create"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using organization, owner;
    end if;
  end;
  perform better_supabase.audit_event(
    event_type => 'organization.created',
    category => 'configuration',
    target_type => 'organization',
    record_id => organization::text,
    tenant => (organization)::uuid,
    metadata => jsonb_build_object('organizationId', organization::text, 'userId', owner, 'role', 'owner')
  );
  return organization;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_team (
  tenant      uuid,
  name        text,
  description text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid;
  v_slug text := trim(both '-' from regexp_replace(lower(create_team.name), '[^a-z0-9]+', '-', 'g'));
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', create_team.tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  if v_slug is null or v_slug = '' then
    raise exception 'team name needs a slug' using errcode = '22023', hint = 'TEAM_SLUG_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_team_create"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using create_team.tenant, v_slug;
    end if;
  end;
  insert into "better_supabase"."teams" ("tenant_id", "name", "slug", "description", "created_by")
  values (create_team.tenant, create_team.name, v_slug, create_team.description, auth.uid())
  returning "id" into v_id;
  perform better_supabase.audit_event(
    event_type => 'team.created',
    category => 'membership',
    target_type => 'team',
    record_id => (v_id)::text,
    tenant => (create_team.tenant)::uuid,
    metadata => jsonb_build_object('organizationId', create_team.tenant, 'id', v_id, 'name', create_team.name)
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_team_create"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using v_id, create_team.tenant;
    end if;
  end;
  return jsonb_build_object('id', v_id, 'slug', v_slug);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_workflow_schedule (
  name     text,
  workflow text,
  cron     text,
  next_run timestamp with time zone,
  payload  jsonb                    DEFAULT '{}'::jsonb,
  timezone text                     DEFAULT 'UTC'::text,
  tenant   uuid                     DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."workflow_schedules"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (tenant is not null and coalesce(better_supabase.can('tenant', tenant, 'workflow.admin'), false))) then
    raise exception 'You may not schedule workflows here' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  insert into "better_supabase"."workflow_schedules" as x ("tenant_id", "name", "workflow", "input", "cron", "timezone", "next_run_at", "created_by")
  values (tenant, name, workflow, coalesce(payload -> 'input', '[]'::jsonb), cron, coalesce(timezone, 'UTC'), next_run, (select auth.uid()))
  on conflict on constraint workflow_schedules_tenant_name_key do update set
    "workflow" = excluded."workflow",
    "input" = excluded."input",
    "cron" = excluded."cron",
    "timezone" = excluded."timezone",
    "next_run_at" = excluded."next_run_at",
    "locked_until" = null
  returning * into v_row;
  return jsonb_build_object(
    'id', v_row."id",
    'tenant', v_row."tenant_id",
    'name', v_row."name",
    'workflow', v_row."workflow",
    'input', v_row."input",
    'cron', v_row."cron",
    'timezone', v_row."timezone",
    'nextRunAt', v_row."next_run_at",
    'lastRunAt', v_row."last_run_at",
    'paused', v_row."paused",
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at"
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.decide_ai_tool_approval (
  approval_id text,
  approved    boolean,
  reason      text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."ai_tool_approvals";
  v_decision text := case when decide_ai_tool_approval.approved then 'approved' else 'denied' end;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."ai_tool_approvals" x where x."approval_id" = decide_ai_tool_approval.approval_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = (select auth.uid())) then
    raise exception 'No approval %', decide_ai_tool_approval.approval_id using errcode = 'P0002', hint = 'AI_APPROVAL_NOT_FOUND';
  end if;
  if decide_ai_tool_approval.approved is null then
    raise exception 'Approve or deny' using errcode = '22023', hint = 'AI_APPROVAL_INVALID';
  end if;
  if v_row."decision" is not null then
    if v_row."decision" = v_decision then
      return jsonb_build_object('approval_id', v_row."approval_id", 'chat_id', v_row."chat_id", 'run_id', v_row."run_id", 'message_id', v_row."message_id", 'tool', v_row."tool", 'tool_call_id', v_row."tool_call_id", 'input', v_row."input", 'decision', v_row."decision", 'reason', v_row."reason", 'signature', v_row."signature", 'decided_by', v_row."decided_by", 'decided_at', v_row."decided_at", 'created_at', v_row."created_at");
    end if;
    raise exception 'Approval % was already %', v_row."approval_id", v_row."decision" using errcode = 'P0001', hint = 'AI_APPROVAL_DECIDED';
  end if;
  update "better_supabase"."ai_tool_approvals" x set
    "decision" = v_decision,
    "reason" = decide_ai_tool_approval.reason,
    "decided_by" = auth.uid(),
    "decided_at" = now()
  where x."approval_id" = v_row."approval_id"
  returning * into v_row;
  perform "better_supabase"."ai_chat_notify"(v_row."chat_id", null, 'approval.decided', jsonb_build_object('approvalId', v_row."approval_id", 'decision', v_decision), false);
  perform better_supabase.audit_event(
    event_type => 'ai_tool_approval.decided',
    category => 'ai',
    target_type => 'ai_tool_approval',
    record_id => v_row."approval_id",
    target_label => v_row."tool",
    tenant => ((select c."organization_id" from "better_supabase"."ai_chats" c where c."id" = v_row."chat_id"))::uuid,
    metadata => jsonb_build_object('organizationId', (select c."organization_id" from "better_supabase"."ai_chats" c where c."id" = v_row."chat_id")::text, 'chatId', v_row."chat_id", 'approvalId', v_row."approval_id", 'tool', v_row."tool", 'decision', v_decision),
    idempotency_key => 'ai_tool_approval.decided:' || v_row."approval_id"
  );
  return jsonb_build_object('approval_id', v_row."approval_id", 'chat_id', v_row."chat_id", 'run_id', v_row."run_id", 'message_id', v_row."message_id", 'tool', v_row."tool", 'tool_call_id', v_row."tool_call_id", 'input', v_row."input", 'decision', v_row."decision", 'reason', v_row."reason", 'signature', v_row."signature", 'decided_by', v_row."decided_by", 'decided_at', v_row."decided_at", 'created_at', v_row."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.decide_connector_fingerprint (
  server_id   uuid,
  fingerprint text,
  approved    boolean
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_server "better_supabase"."connector_servers"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_server from "better_supabase"."connector_servers" x where x."id" = decide_connector_fingerprint.server_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_server."organization_id", 'ai.admin'), false)) then
    raise exception 'connector % not found', decide_connector_fingerprint.server_id using errcode = 'P0002', hint = 'CONNECTOR_NOT_FOUND';
  end if;
  update "better_supabase"."connector_tool_fingerprints" p set
    "status" = case when decide_connector_fingerprint.approved then 'approved' else 'rejected' end,
    "approved_by" = auth.uid(), "approved_at" = now()
  where p."server_id" = v_server."id" and p."fingerprint" = decide_connector_fingerprint.fingerprint;
  if not found then
    return false;
  end if;
  perform better_supabase.audit_event(
    event_type => 'connector.fingerprint_decided',
    category => 'integration',
    target_type => 'connector',
    record_id => v_server."id"::text,
    target_label => v_server."name",
    tenant => (v_server."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_server."organization_id"::text, 'serverId', v_server."id", 'name', v_server."name", 'fingerprint', decide_connector_fingerprint.fingerprint, 'approved', decide_connector_fingerprint.approved)
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.decline_invitation (
  token text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  declined_id uuid;
  tenant text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "better_supabase"."invitations" i set "declined_at" = now() where i."token_hash" = encode(extensions.digest(token, 'sha256'), 'hex') and i."expires_at" >= now() and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
  returning i."id", i."organization_id"::text into declined_id, tenant;
  if declined_id is not null then
    perform better_supabase.audit_event(
    event_type => 'invitation.declined',
    category => 'membership',
    target_type => 'invitation',
    record_id => declined_id::text,
    tenant => (tenant)::uuid,
    metadata => jsonb_build_object('invitationId', declined_id, 'organizationId', tenant)
  );
    return true;
  end if;
  return false;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.decline_invitation_by_id (
  invitation_id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  declined_id uuid;
  tenant text;
  invitee_email text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select lower(u.email) into invitee_email
  from auth.users u
  where u.id = auth.uid() and u.email_confirmed_at is not null;
  if invitee_email is null then
    return false;
  end if;
  update "better_supabase"."invitations" i set "declined_at" = now() where i."id" = invitation_id and lower(i."email") = invitee_email and i."expires_at" >= now() and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
  returning i."id", i."organization_id"::text into declined_id, tenant;
  if declined_id is not null then
    perform better_supabase.audit_event(
    event_type => 'invitation.declined',
    category => 'membership',
    target_type => 'invitation',
    record_id => declined_id::text,
    tenant => (tenant)::uuid,
    metadata => jsonb_build_object('invitationId', declined_id, 'organizationId', tenant)
  );
    return true;
  end if;
  return false;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_agent (
  id uuid
)
  RETURNS boolean
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
  select * into v_row from "better_supabase"."agents" x where x."id" = delete_agent.id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai.moderate'), false)) then
    return false;
  end if;
  delete from "better_supabase"."agents" x where x."id" = v_row."id";
  perform better_supabase.audit_event(
    event_type => 'agent.deleted',
    category => 'ai',
    target_type => 'agent',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'agentId', v_row."id", 'slug', v_row."slug")
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_ai_chat (
  chat uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."ai_chats";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."ai_chats" x where x."id" = delete_ai_chat.chat for update;
  if not found then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = (select auth.uid()) or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai_chat.admin'), false)) then
    raise exception 'No chat %', delete_ai_chat.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  delete from "better_supabase"."ai_chats" x where x."id" = delete_ai_chat.chat;
  perform "better_supabase"."ai_chat_notify"(v_row."id", v_row."owner_id", 'chat.deleted', '{}'::jsonb, true);
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_ai_document (
  document_id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."ai_documents"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."ai_documents" x where x."id" = delete_ai_document.document_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai.admin'), false)) then
    return false;
  end if;
  delete from "better_supabase"."ai_documents" x where x."id" = v_row."id";
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_ai_file (
  file_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."ai_files"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."ai_files" x where x."id" = delete_ai_file.file_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai.admin'), false)) then
    return null;
  end if;
  delete from "better_supabase"."ai_files" x where x."id" = v_row."id";
  return jsonb_build_object('bucket', v_row."bucket", 'path', v_row."path");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_ai_project (
  id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from "better_supabase"."ai_projects" x where x."id" = delete_ai_project.id and x."owner_id" = (select auth.uid());
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
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

CREATE OR REPLACE FUNCTION better_supabase.delete_ai_task (
  id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid := delete_ai_task.id;
  v_row "better_supabase"."ai_scheduled_tasks"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."ai_scheduled_tasks" x where x."id" = v_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."user_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai.admin'), false)) then
    return false;
  end if;
  delete from "better_supabase"."ai_scheduled_tasks" x where x."id" = v_id;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_announcement (
  id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.is_platform('announcements.manage'), false)) then
    raise exception 'You may not manage announcements' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  delete from "better_supabase"."announcements" x where x."id" = delete_announcement.id;
  get diagnostics v_count = row_count;
  if v_count > 0 then
    perform better_supabase.audit_event(
    event_type => 'announcement.deleted',
    category => 'configuration',
    target_type => 'announcement',
    record_id => delete_announcement.id::text,
    metadata => jsonb_build_object('announcementId', delete_announcement.id)
  );
  end if;
  return v_count > 0;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_connector_server (
  id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."connector_servers"%rowtype;
  v_grants jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."connector_servers" x where x."id" = delete_connector_server.id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai.admin'), false)) then
    raise exception 'connector % not found', delete_connector_server.id using errcode = 'P0002', hint = 'CONNECTOR_NOT_FOUND';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'user_id', y."user_id", 'server_id', y."server_id", 'organization_id', y."organization_id", 'credential_ref', y."credential_ref", 'scopes', y."scopes", 'expires_at', y."expires_at", 'granted_at', y."granted_at", 'revoked_at', y."revoked_at")), '[]') into v_grants
  from "better_supabase"."connector_grants" y where y."server_id" = v_row."id" and y."revoked_at" is null;
  delete from "better_supabase"."connector_servers" x where x."id" = v_row."id";
  perform better_supabase.audit_event(
    event_type => 'connector.deleted',
    category => 'integration',
    target_type => 'connector',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'serverId', v_row."id", 'name', v_row."name")
  );
  return v_grants;
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.is_platform('flags.manage'), false)) then
    raise exception 'Not allowed to manage feature flags' using errcode = '42501', hint = 'FLAGS_FORBIDDEN';
  end if;
  delete from "better_supabase"."flags" x where x."key" = delete_flag.key;
  if not found then
    return false;
  end if;
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

CREATE OR REPLACE FUNCTION better_supabase.delete_knowledge_document (
  document_id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."knowledge_documents"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."knowledge_documents" x where x."id" = delete_knowledge_document.document_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai.admin'), false)) then
    return false;
  end if;
  delete from "better_supabase"."knowledge_documents" x where x."id" = v_row."id";
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_message_template (
  template uuid
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
  select "tenant_id" into v_tenant from "better_supabase"."message_templates" where "id" = delete_message_template.template;
  if not found then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'inbox.manage'), false)) then
    raise exception 'not allowed to manage templates' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  delete from "better_supabase"."message_templates" t where t."id" = delete_message_template.template;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_organization (
  organization uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not coalesce(better_supabase.member_can(auth.uid(), organization, 'organization.delete'), false) then
    raise exception 'Not allowed to delete the organization' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  delete from "public"."organizations" where "id" = organization;
  if not found then
    return false;
  end if;
  delete from "public"."memberships" where "organization_id" = organization;
  perform better_supabase.audit_event(
    event_type => 'organization.deleted',
    category => 'configuration',
    target_type => 'organization',
    record_id => organization::text,
    tenant => (organization)::uuid,
    metadata => jsonb_build_object('mode', 'hard')
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_team (
  team uuid
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
  select "tenant_id" into v_tenant from "better_supabase"."teams" where "id" = delete_team.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  delete from "better_supabase"."teams" where "id" = delete_team.team;
  perform better_supabase.audit_event(
    event_type => 'team.deleted',
    category => 'membership',
    target_type => 'team',
    record_id => (delete_team.team)::text,
    tenant => (v_tenant)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'id', delete_team.team)
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.dismiss_announcement (
  id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_dismissible boolean;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null then
    raise exception 'Sign in first' using errcode = '42501', hint = 'ANNOUNCEMENT_FORBIDDEN';
  end if;
  select x."dismissible" into v_dismissible from "better_supabase"."announcements" x where x."id" = dismiss_announcement.id;
  if v_dismissible is null then
    raise exception 'No announcement %', dismiss_announcement.id using errcode = 'P0002', hint = 'ANNOUNCEMENT_NOT_FOUND';
  end if;
  if not v_dismissible then
    raise exception 'This announcement can''t be dismissed' using errcode = '22023', hint = 'ANNOUNCEMENT_NOT_DISMISSIBLE';
  end if;
  insert into "better_supabase"."announcement_dismissals" ("announcement_id", "user_id") values (dismiss_announcement.id, auth.uid())
  on conflict do nothing;
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.dismiss_notifications (
  ids uuid[]
)
  RETURNS jsonb
  LANGUAGE sql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select better_supabase.raise_actor_readonly() where not (better_supabase.actor_may_write());

  with rc as (
    update "better_supabase"."notification_recipients" rc
    set "dismissed_at" = now(), "read_at" = coalesce(rc."read_at", now())
    where rc."user_id" = auth.uid()
      and rc."dismissed_at" is null
      and rc."id" = any(dismiss_notifications.ids)
    returning rc.*
  )
  select jsonb_build_object(
    'count', count(*),
    'items', coalesce(jsonb_agg(jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'priority', ev."priority", 'resolved_at', rc."resolved_at") order by rc."created_at" desc, rc."id" desc) filter (where rc."user_id" = auth.uid()), '[]')
  )
  from rc
  join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
$function$;

CREATE OR REPLACE FUNCTION better_supabase.edit_message (
  message uuid,
  body    text    DEFAULT NULL::text,
  remove  boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_msg "better_supabase"."inbox_messages"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_msg from "better_supabase"."inbox_messages" where "id" = edit_message.message for update;
  if not found then
    raise exception 'message not found' using errcode = 'P0002', hint = 'MESSAGE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_msg."author_id" is not null and v_msg."author_id" = (select auth.uid()))) then
    raise exception 'only the author edits a message' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  if v_msg."deleted_at" is not null then
    raise exception 'message is deleted' using errcode = '22023', hint = 'MESSAGE_DELETED';
  end if;
  update "better_supabase"."inbox_messages" set
    "body" = case when coalesce(remove, false) then '' else coalesce(edit_message.body, "body") end,
    "attachments" = case when coalesce(remove, false) then '[]'::jsonb else "attachments" end,
    "deleted_at" = case when coalesce(remove, false) then now() end,
    "edited_at" = case when coalesce(remove, false) then "edited_at" else now() end
  where "id" = v_msg."id"
  returning * into v_msg;
  return to_jsonb(v_msg);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.install_agent (
  tenant    uuid,
  agent_id  uuid,
  installed boolean DEFAULT true
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null or not coalesce(better_supabase.can('tenant', install_agent.tenant, 'ai.read'), false) then
    raise exception 'you may not use agents here' using errcode = '42501', hint = 'AGENT_FORBIDDEN';
  end if;
  if not install_agent.installed then
    delete from "better_supabase"."agent_installs" n where n."agent_id" = install_agent.agent_id and n."user_id" = auth.uid() and n."organization_id" = install_agent.tenant;
    get diagnostics v_count = row_count;
    update "better_supabase"."agents" x set "install_count" = greatest(x."install_count" - v_count, 0) where x."id" = install_agent.agent_id;
    if v_count > 0 then
      perform better_supabase.audit_event(
    event_type => 'agent.uninstalled',
    category => 'ai',
    target_type => 'agent',
    record_id => install_agent.agent_id::text,
    tenant => (install_agent.tenant)::uuid,
    metadata => jsonb_build_object('organizationId', install_agent.tenant::text, 'agentId', install_agent.agent_id, 'userId', auth.uid())
  );
    end if;
    return v_count > 0;
  end if;
  if not exists (select 1 from "better_supabase"."agents" x where x."id" = install_agent.agent_id and (x."owner_id" = (select auth.uid()) or (x."published_at" is not null and (x."visibility" = 'public' or (x."visibility" = 'organization' and x."organization_id" in (select better_supabase.tenant_ids_with('ai.read'))))) or x."organization_id" in (select better_supabase.tenant_ids_with('ai.moderate')))) then
    raise exception 'agent % not found', install_agent.agent_id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  insert into "better_supabase"."agent_installs" ("agent_id", "user_id", "organization_id") values (install_agent.agent_id, auth.uid(), install_agent.tenant)
  on conflict do nothing;
  get diagnostics v_count = row_count;
  update "better_supabase"."agents" x set "install_count" = x."install_count" + v_count where x."id" = install_agent.agent_id;
  if v_count > 0 then
    perform better_supabase.audit_event(
    event_type => 'agent.installed',
    category => 'ai',
    target_type => 'agent',
    record_id => install_agent.agent_id::text,
    tenant => (install_agent.tenant)::uuid,
    metadata => jsonb_build_object('organizationId', install_agent.tenant::text, 'agentId', install_agent.agent_id, 'userId', auth.uid())
  );
  end if;
  return v_count > 0;
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
    raise exception 'Platform invitations need platform roles: sql.modules.access.model ''catalog'' with platform assignments, or sql.modules.invitations.options.platformRoles under ''provider''' using errcode = '0A000', hint = 'INVITATION_SCOPE_UNSUPPORTED';
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

CREATE OR REPLACE FUNCTION better_supabase.leave_organization (
  organization uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  me uuid := auth.uid();
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from "public"."memberships" where "organization_id" = organization and "user_id" = me;
  if not found then
    raise exception 'Not a member' using errcode = 'P0002', hint = 'ORGANIZATION_NOT_MEMBER';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_member_change"(uuid, uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text)', v_hook::oid::regproc)
        using organization, me, 'left';
    end if;
  end;
  perform better_supabase.audit_event(
    event_type => 'organization.member_left',
    category => 'membership',
    target_type => 'user',
    record_id => me::text,
    tenant => (organization)::uuid,
    metadata => jsonb_build_object('organizationId', organization::text, 'userId', me)
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_teams (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', t."id",
    'name', t."name",
    'slug', t."slug",
    'status', t."status"
  )), '[]'::jsonb)
  from "better_supabase"."teams" t
  where t."tenant_id" = list_teams.tenant
    and (
      auth.role() = 'service_role'
      or coalesce(better_supabase.can('tenant', list_teams.tenant, 'teams.read'), false)
    )
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
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if (select auth.uid()) is null or not "better_supabase"."inbox_conversation_allowed"(conversation::text) then
    raise exception 'not allowed to read this conversation' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  insert into "better_supabase"."conversation_reads" ("conversation_id", "user_id", "last_read_at")
  values (conversation, (select auth.uid()), v_at)
  on conflict ("conversation_id", "user_id") do update set "last_read_at" = excluded."last_read_at";
  return v_at;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.mark_notifications_read (
  ids    uuid[] DEFAULT NULL::uuid[],
  tenant uuid   DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select better_supabase.raise_actor_readonly() where not (better_supabase.actor_may_write());

  with rc as (
    update "better_supabase"."notification_recipients" rc set "read_at" = now()
    where rc."user_id" = auth.uid()
      and rc."read_at" is null
      and rc."dismissed_at" is null
      and (mark_notifications_read.ids is null or rc."id" = any(mark_notifications_read.ids))
      and (mark_notifications_read.tenant is null or rc."organization_id" = mark_notifications_read.tenant)
    returning rc.*
  )
  select jsonb_build_object(
    'count', count(*),
    'items', coalesce(jsonb_agg(jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'priority', ev."priority", 'resolved_at', rc."resolved_at") order by rc."created_at" desc, rc."id" desc) filter (where rc."user_id" = auth.uid()), '[]')
  )
  from rc
  join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
$function$;

CREATE OR REPLACE FUNCTION better_supabase.mark_notifications_unread (
  ids    uuid[],
  tenant uuid   DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select better_supabase.raise_actor_readonly() where not (better_supabase.actor_may_write());

  with rc as (
    update "better_supabase"."notification_recipients" rc set "read_at" = null
    where rc."user_id" = auth.uid()
      and rc."read_at" is not null
      and rc."dismissed_at" is null
      and rc."id" = any(mark_notifications_unread.ids)
      and (mark_notifications_unread.tenant is null or rc."organization_id" = mark_notifications_unread.tenant)
    returning rc.*
  )
  select jsonb_build_object(
    'count', count(*),
    'items', coalesce(jsonb_agg(jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'priority', ev."priority", 'resolved_at', rc."resolved_at") order by rc."created_at" desc, rc."id" desc) filter (where rc."user_id" = auth.uid()), '[]')
  )
  from rc
  join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
$function$;

CREATE OR REPLACE FUNCTION better_supabase.mark_used (
  organization uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "public"."memberships" set "last_used_at" = now()
  where "organization_id" = organization and "user_id" = auth.uid();
  return found;
end;
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
  v_owner := case when v_scope = 'organization' then null when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then (memory_create.ns ->> 'owner_id')::uuid else auth.uid() end;
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and (auth.uid() is null or not coalesce(better_supabase.can('tenant', memory_create.tenant, 'ai.read'), false)) then
    raise exception 'you may not use memory here' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if v_scope not in ('user', 'agent', 'chat', 'project', 'organization')
    or (v_scope = 'agent') <> (v_agent is not null)
    or (v_scope = 'chat') <> (v_chat is not null)
    or (v_scope = 'project') <> (v_project is not null)
    or (v_scope <> 'organization' and v_owner is null) then
    raise exception 'ns % is not a memory namespace', memory_create.ns using errcode = '22023', hint = 'MEMORY_NAMESPACE';
  end if;
  if v_scope = 'organization' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', memory_create.tenant, 'ai.admin'), false)) then
    raise exception 'only admins change organization memory' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if memory_create.path is null or length(memory_create.path) > 500 or memory_create.path !~ '^/memories(/[A-Za-z0-9._ -]+)*$' or memory_create.path ~ '(^|/)[.]{1,2}(/|$)' then
    raise exception '% is not a path under /memories', memory_create.path using errcode = '22023', hint = 'MEMORY_PATH';
  end if;
  if length(memory_create.content) > 100000 then
    raise exception 'memory content is limited to % characters', 100000 using errcode = '22023', hint = 'MEMORY_TOO_LARGE';
  end if;
  select * into v_row from "better_supabase"."memories" x
  where x."organization_id" = memory_create.tenant and x."owner_id" is not distinct from v_owner and x."scope" = v_scope and x."agent_id" is not distinct from v_agent and x."chat_id" is not distinct from v_chat and x."project_id" is not distinct from v_project and x."superseded_by" is null and x."path" = memory_create.path
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
    insert into "better_supabase"."memories" ("organization_id", "owner_id", "scope", "agent_id", "chat_id", "project_id", "kind", "path", "content")
    values (memory_create.tenant, v_owner, v_scope, v_agent, v_chat, v_project, 'core', memory_create.path, memory_create.content)
    returning * into v_row;
  end if;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'scope', v_row."scope", 'agent_id', v_row."agent_id", 'chat_id', v_row."chat_id", 'project_id', v_row."project_id", 'kind', v_row."kind", 'path', v_row."path", 'content', v_row."content", 'version', v_row."version", 'embedding_model', v_row."embedding_model", 'source_message_id', v_row."source_message_id", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
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
  v_owner := case when v_scope = 'organization' then null when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then (memory_delete.ns ->> 'owner_id')::uuid else auth.uid() end;
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and (auth.uid() is null or not coalesce(better_supabase.can('tenant', memory_delete.tenant, 'ai.read'), false)) then
    raise exception 'you may not use memory here' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if v_scope not in ('user', 'agent', 'chat', 'project', 'organization')
    or (v_scope = 'agent') <> (v_agent is not null)
    or (v_scope = 'chat') <> (v_chat is not null)
    or (v_scope = 'project') <> (v_project is not null)
    or (v_scope <> 'organization' and v_owner is null) then
    raise exception 'ns % is not a memory namespace', memory_delete.ns using errcode = '22023', hint = 'MEMORY_NAMESPACE';
  end if;
  if v_scope = 'organization' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', memory_delete.tenant, 'ai.admin'), false)) then
    raise exception 'only admins change organization memory' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if memory_delete.path is null or length(memory_delete.path) > 500 or memory_delete.path !~ '^/memories(/[A-Za-z0-9._ -]+)*$' or memory_delete.path ~ '(^|/)[.]{1,2}(/|$)' then
    raise exception '% is not a path under /memories', memory_delete.path using errcode = '22023', hint = 'MEMORY_PATH';
  end if;
  delete from "better_supabase"."memories" x
  where x."organization_id" = memory_delete.tenant and x."owner_id" is not distinct from v_owner and x."scope" = v_scope and x."agent_id" is not distinct from v_agent and x."chat_id" is not distinct from v_chat and x."project_id" is not distinct from v_project and x."superseded_by" is null
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
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = auth.uid() or (v_row."scope" = 'organization' and coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai.admin'), false))) then
    return false;
  end if;
  if memory_forget.superseded_by is null then
    delete from "better_supabase"."memories" x where x."id" = v_row."id";
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
  v_owner := case when v_scope = 'organization' then null when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then (memory_insert.ns ->> 'owner_id')::uuid else auth.uid() end;
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and (auth.uid() is null or not coalesce(better_supabase.can('tenant', memory_insert.tenant, 'ai.read'), false)) then
    raise exception 'you may not use memory here' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if v_scope not in ('user', 'agent', 'chat', 'project', 'organization')
    or (v_scope = 'agent') <> (v_agent is not null)
    or (v_scope = 'chat') <> (v_chat is not null)
    or (v_scope = 'project') <> (v_project is not null)
    or (v_scope <> 'organization' and v_owner is null) then
    raise exception 'ns % is not a memory namespace', memory_insert.ns using errcode = '22023', hint = 'MEMORY_NAMESPACE';
  end if;
  if v_scope = 'organization' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', memory_insert.tenant, 'ai.admin'), false)) then
    raise exception 'only admins change organization memory' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if memory_insert.path is null or length(memory_insert.path) > 500 or memory_insert.path !~ '^/memories(/[A-Za-z0-9._ -]+)*$' or memory_insert.path ~ '(^|/)[.]{1,2}(/|$)' then
    raise exception '% is not a path under /memories', memory_insert.path using errcode = '22023', hint = 'MEMORY_PATH';
  end if;
  select * into v_row from "better_supabase"."memories" x
  where x."organization_id" = memory_insert.tenant and x."owner_id" is not distinct from v_owner and x."scope" = v_scope and x."agent_id" is not distinct from v_agent and x."chat_id" is not distinct from v_chat and x."project_id" is not distinct from v_project and x."superseded_by" is null and x."path" = memory_insert.path
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
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'scope', v_row."scope", 'agent_id', v_row."agent_id", 'chat_id', v_row."chat_id", 'project_id', v_row."project_id", 'kind', v_row."kind", 'path', v_row."path", 'content', v_row."content", 'version', v_row."version", 'embedding_model', v_row."embedding_model", 'source_message_id', v_row."source_message_id", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
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
  v_owner := case when v_scope = 'organization' then null when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then (memory_rename.ns ->> 'owner_id')::uuid else auth.uid() end;
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and (auth.uid() is null or not coalesce(better_supabase.can('tenant', memory_rename.tenant, 'ai.read'), false)) then
    raise exception 'you may not use memory here' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if v_scope not in ('user', 'agent', 'chat', 'project', 'organization')
    or (v_scope = 'agent') <> (v_agent is not null)
    or (v_scope = 'chat') <> (v_chat is not null)
    or (v_scope = 'project') <> (v_project is not null)
    or (v_scope <> 'organization' and v_owner is null) then
    raise exception 'ns % is not a memory namespace', memory_rename.ns using errcode = '22023', hint = 'MEMORY_NAMESPACE';
  end if;
  if v_scope = 'organization' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', memory_rename.tenant, 'ai.admin'), false)) then
    raise exception 'only admins change organization memory' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
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
    where x."organization_id" = memory_rename.tenant and x."owner_id" is not distinct from v_owner and x."scope" = v_scope and x."agent_id" is not distinct from v_agent and x."chat_id" is not distinct from v_chat and x."project_id" is not distinct from v_project and x."superseded_by" is null
      and (x."path" = memory_rename.new_path or x."path" like replace(replace(memory_rename.new_path, '_', '\_'), '%', '\%') || '/%')
  ) then
    raise exception '% already exists', memory_rename.new_path using errcode = '23505', hint = 'MEMORY_EXISTS';
  end if;
  update "better_supabase"."memories" x set
    "path" = memory_rename.new_path || substr(x."path", length(memory_rename.old_path) + 1),
    "version" = x."version" + 1, "updated_at" = now()
  where x."organization_id" = memory_rename.tenant and x."owner_id" is not distinct from v_owner and x."scope" = v_scope and x."agent_id" is not distinct from v_agent and x."chat_id" is not distinct from v_chat and x."project_id" is not distinct from v_project and x."superseded_by" is null
    and (x."path" = memory_rename.old_path or x."path" like v_prefix);
  get diagnostics v_count = row_count;
  if v_count = 0 then
    raise exception '% not found', memory_rename.old_path using errcode = 'P0002', hint = 'MEMORY_NOT_FOUND';
  end if;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.memory_save (
  tenant            uuid,
  content           text,
  ns                jsonb             DEFAULT '{}'::jsonb,
  embedding         extensions.vector DEFAULT NULL::extensions.vector,
  model             text              DEFAULT NULL::text,
  source_message_id text              DEFAULT NULL::text
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
  v_owner := case when v_scope = 'organization' then null when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then (memory_save.ns ->> 'owner_id')::uuid else auth.uid() end;
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and (auth.uid() is null or not coalesce(better_supabase.can('tenant', memory_save.tenant, 'ai.read'), false)) then
    raise exception 'you may not use memory here' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if v_scope not in ('user', 'agent', 'chat', 'project', 'organization')
    or (v_scope = 'agent') <> (v_agent is not null)
    or (v_scope = 'chat') <> (v_chat is not null)
    or (v_scope = 'project') <> (v_project is not null)
    or (v_scope <> 'organization' and v_owner is null) then
    raise exception 'ns % is not a memory namespace', memory_save.ns using errcode = '22023', hint = 'MEMORY_NAMESPACE';
  end if;
  if v_scope = 'organization' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', memory_save.tenant, 'ai.admin'), false)) then
    raise exception 'only admins change organization memory' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if coalesce(length(memory_save.content), 0) = 0 then
    raise exception 'memory content is empty' using errcode = '22023', hint = 'MEMORY_EMPTY';
  end if;
  if length(memory_save.content) > 100000 then
    raise exception 'memory content is limited to % characters', 100000 using errcode = '22023', hint = 'MEMORY_TOO_LARGE';
  end if;
  insert into "better_supabase"."memories" ("organization_id", "owner_id", "scope", "agent_id", "chat_id", "project_id", "kind", "content", "embedding", "embedding_model", "source_message_id")
  values (memory_save.tenant, v_owner, v_scope, v_agent, v_chat, v_project, 'archival', memory_save.content, memory_save.embedding, memory_save.model, memory_save.source_message_id)
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'scope', v_row."scope", 'agent_id', v_row."agent_id", 'chat_id', v_row."chat_id", 'project_id', v_row."project_id", 'kind', v_row."kind", 'path', v_row."path", 'content', v_row."content", 'version', v_row."version", 'embedding_model', v_row."embedding_model", 'source_message_id', v_row."source_message_id", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
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
  v_owner := case when v_scope = 'organization' then null when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then (memory_str_replace.ns ->> 'owner_id')::uuid else auth.uid() end;
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and (auth.uid() is null or not coalesce(better_supabase.can('tenant', memory_str_replace.tenant, 'ai.read'), false)) then
    raise exception 'you may not use memory here' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if v_scope not in ('user', 'agent', 'chat', 'project', 'organization')
    or (v_scope = 'agent') <> (v_agent is not null)
    or (v_scope = 'chat') <> (v_chat is not null)
    or (v_scope = 'project') <> (v_project is not null)
    or (v_scope <> 'organization' and v_owner is null) then
    raise exception 'ns % is not a memory namespace', memory_str_replace.ns using errcode = '22023', hint = 'MEMORY_NAMESPACE';
  end if;
  if v_scope = 'organization' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', memory_str_replace.tenant, 'ai.admin'), false)) then
    raise exception 'only admins change organization memory' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if memory_str_replace.path is null or length(memory_str_replace.path) > 500 or memory_str_replace.path !~ '^/memories(/[A-Za-z0-9._ -]+)*$' or memory_str_replace.path ~ '(^|/)[.]{1,2}(/|$)' then
    raise exception '% is not a path under /memories', memory_str_replace.path using errcode = '22023', hint = 'MEMORY_PATH';
  end if;
  select * into v_row from "better_supabase"."memories" x
  where x."organization_id" = memory_str_replace.tenant and x."owner_id" is not distinct from v_owner and x."scope" = v_scope and x."agent_id" is not distinct from v_agent and x."chat_id" is not distinct from v_chat and x."project_id" is not distinct from v_project and x."superseded_by" is null and x."path" = memory_str_replace.path
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
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'scope', v_row."scope", 'agent_id', v_row."agent_id", 'chat_id', v_row."chat_id", 'project_id', v_row."project_id", 'kind', v_row."kind", 'path', v_row."path", 'content', v_row."content", 'version', v_row."version", 'embedding_model', v_row."embedding_model", 'source_message_id', v_row."source_message_id", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.pause_workflow_schedule (
  schedule uuid,
  paused   boolean DEFAULT true
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "better_supabase"."workflow_schedules" x set "paused" = coalesce(paused, true)
  where x."id" = schedule
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (x."tenant_id" is not null and coalesce(better_supabase.can('tenant', x."tenant_id", 'workflow.admin'), false)));
  return found;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.publish_agent (
  id         uuid,
  visibility text
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
  if publish_agent.visibility is null or publish_agent.visibility not in ('private', 'organization', 'public') then
    raise exception 'visibility is private, organization or public' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select * into v_row from "better_supabase"."agents" x where x."id" = publish_agent.id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai.moderate'), false)) then
    raise exception 'agent % not found', publish_agent.id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  if publish_agent.visibility <> 'private' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai.moderate'), false)
    or (v_row."owner_id" = auth.uid() and coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai.share'), false))) then
    raise exception 'you may not publish agents here' using errcode = '42501', hint = 'AGENT_FORBIDDEN';
  end if;
  update "better_supabase"."agents" x set
    "visibility" = publish_agent.visibility,
    "published_at" = case when publish_agent.visibility = 'private' then null else coalesce(x."published_at", now()) end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform better_supabase.audit_event(
    event_type => 'agent.published',
    category => 'ai',
    target_type => 'agent',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'agentId', v_row."id", 'slug', v_row."slug", 'visibility', publish_agent.visibility)
  );
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
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
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."workflow_versions" x where x."id" = version for update;
  if not found then
    raise exception 'No such workflow version' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."workflow_definitions" x where x."id" = v_row."definition_id";
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'workflow.publish'), false))) then
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
    'graph', v_row."graph",
    'compiled', v_row."compiled"
  );
  end if;
  v_errors := "better_supabase"."validate_workflow_graph"(v_row."graph");
  if jsonb_array_length(v_errors) > 0 then
    raise exception '%', (select string_agg(value, '; ') from jsonb_array_elements_text(v_errors))
      using errcode = '22023', hint = 'WORKFLOW_GRAPH_INVALID';
  end if;
  update "better_supabase"."workflow_versions" x set "status" = 'archived'
  where x."definition_id" = v_row."definition_id" and x."status" = 'published';
  update "better_supabase"."workflow_versions" x set "status" = 'published', "compiled" = compiled, "published_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
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
    'graph', v_row."graph",
    'compiled', v_row."compiled"
  );
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
  v_conversations integer;
  v_messages integer;
  v_paths jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select c."tenant_id" into v_tenant from "better_supabase"."contacts" c where c."id" = purge_contact.contact;
  if not found then
    raise exception 'contact not found' using errcode = 'P0002', hint = 'CONTACT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'inbox.manage'), false)) then
    raise exception 'not allowed to erase contacts' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  select count(*)::integer into v_conversations from "better_supabase"."conversations" v where v."contact_id" = purge_contact.contact;
  select coalesce(jsonb_agg(a ->> 'path') filter (where a ? 'path'), '[]'::jsonb)
  into v_paths
  from "better_supabase"."inbox_messages" m
  join "better_supabase"."conversations" v on v."id" = m."conversation_id"
  left join lateral jsonb_array_elements(m."attachments") a on true
  where v."contact_id" = purge_contact.contact;
  select count(*)::integer into v_messages
  from "better_supabase"."inbox_messages" m
  join "better_supabase"."conversations" v on v."id" = m."conversation_id"
  where v."contact_id" = purge_contact.contact;
  delete from "better_supabase"."contacts" c where c."id" = purge_contact.contact;
  return jsonb_build_object('conversations', v_conversations, 'messages', v_messages, 'attachments', v_paths);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.raise_actor_readonly()
  RETURNS void
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.rate_agent (
  agent_id uuid,
  rating   integer,
  comment  text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_old integer;
  v_row "better_supabase"."agents"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null then
    raise exception 'sign in to rate agents' using errcode = '42501', hint = 'AGENT_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."agents" x where x."id" = rate_agent.agent_id and (x."owner_id" = (select auth.uid()) or (x."published_at" is not null and (x."visibility" = 'public' or (x."visibility" = 'organization' and x."organization_id" in (select better_supabase.tenant_ids_with('ai.read'))))) or x."organization_id" in (select better_supabase.tenant_ids_with('ai.moderate'))) for update;
  if not found then
    raise exception 'agent % not found', rate_agent.agent_id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  if rate_agent.rating is not null and rate_agent.rating not between 1 and 5 then
    raise exception 'a rating is 1 to 5' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  delete from "better_supabase"."agent_ratings" g where g."agent_id" = v_row."id" and g."user_id" = auth.uid()
  returning g."rating" into v_old;
  if rate_agent.rating is not null then
    insert into "better_supabase"."agent_ratings" ("agent_id", "user_id", "rating", "comment")
    values (v_row."id", auth.uid(), rate_agent.rating, rate_agent.comment);
  end if;
  update "better_supabase"."agents" x set
    "rating_count" = x."rating_count" - (case when v_old is null then 0 else 1 end) + (case when rate_agent.rating is null then 0 else 1 end),
    "rating_sum" = x."rating_sum" - coalesce(v_old, 0) + coalesce(rate_agent.rating, 0)
  where x."id" = v_row."id"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.rate_ai_message (
  chat       uuid,
  message_id text,
  rating     integer,
  reason     text    DEFAULT NULL::text,
  comment    text    DEFAULT NULL::text
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
  if auth.uid() is null or not "better_supabase"."ai_chat_can_read"(rate_ai_message.chat) then
    raise exception 'No chat %', rate_ai_message.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  if not exists (select 1 from "better_supabase"."ai_messages" x where x."chat_id" = rate_ai_message.chat and x."id" = rate_ai_message.message_id) then
    raise exception 'No message %', rate_ai_message.message_id using errcode = 'P0002', hint = 'AI_MESSAGE_NOT_FOUND';
  end if;
  if rate_ai_message.rating is null then
    delete from "better_supabase"."ai_message_feedback" x
    where x."chat_id" = rate_ai_message.chat and x."message_id" = rate_ai_message.message_id and x."user_id" = auth.uid();
    return null;
  end if;
  insert into "better_supabase"."ai_message_feedback" ("chat_id", "message_id", "user_id", "rating", "reason", "comment")
  values (rate_ai_message.chat, rate_ai_message.message_id, auth.uid(), rate_ai_message.rating, rate_ai_message.reason, rate_ai_message.comment)
  on conflict ("chat_id", "message_id", "user_id") do update set
    "rating" = excluded."rating", "reason" = excluded."reason", "comment" = excluded."comment", "updated_at" = now();
  return jsonb_build_object('chat_id', rate_ai_message.chat, 'message_id', rate_ai_message.message_id, 'rating', rate_ai_message.rating, 'reason', rate_ai_message.reason, 'comment', rate_ai_message.comment);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.react_to_message (
  message uuid,
  emoji   text,
  present boolean DEFAULT true,
  actor   text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_msg "better_supabase"."inbox_messages"%rowtype;
  v_who text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_msg from "better_supabase"."inbox_messages" where "id" = react_to_message.message for update;
  if not found then
    raise exception 'message not found' using errcode = 'P0002', hint = 'MESSAGE_NOT_FOUND';
  end if;
  if coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    v_who := coalesce(actor, 'bot');
  elsif v_msg."kind" = 'message' and "better_supabase"."inbox_conversation_allowed"(v_msg."conversation_id"::text, true) then
    v_who := (select auth.uid())::text;
  elsif v_msg."kind" = 'note' and coalesce(better_supabase.can('tenant', v_msg."tenant_id", 'inbox.reply'), false) then
    v_who := (select auth.uid())::text;
  else
    raise exception 'not allowed to react to this message' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  if length(emoji) not between 1 and 64 then
    raise exception 'emoji must be 1 to 64 characters' using errcode = '22023', hint = 'INBOX_REACTION_INVALID';
  end if;
  update "better_supabase"."inbox_messages" set "reactions" = case
    when coalesce(present, true) then
      "reactions" || jsonb_build_object(emoji, (
        select coalesce(jsonb_agg(distinct x), '[]'::jsonb)
        from jsonb_array_elements_text(coalesce("reactions" -> emoji, '[]'::jsonb) || to_jsonb(v_who)) x
      ))
    else
      case when (select count(*) from jsonb_array_elements_text(coalesce("reactions" -> emoji, '[]'::jsonb)) x where x <> v_who) = 0
        then "reactions" - emoji
        else "reactions" || jsonb_build_object(emoji, (select jsonb_agg(x) from jsonb_array_elements_text("reactions" -> emoji) x where x <> v_who))
      end
    end
  where "id" = v_msg."id"
  returning * into v_msg;
  return v_msg."reactions";
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_ai_batch (
  tenant    uuid,
  provider  text,
  reference jsonb,
  fields    jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."ai_batches"%rowtype;
  v_fields jsonb := coalesce(record_ai_batch.fields, '{}');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (auth.uid() is not null and coalesce(better_supabase.can('tenant', record_ai_batch.tenant, 'ai.create'), false))) then
    raise exception 'you may not start batches here' using errcode = '42501', hint = 'AI_BATCH_FORBIDDEN';
  end if;
  insert into "better_supabase"."ai_batches" ("organization_id", "user_id", "provider", "reference", "status", "raw_status", "item_count", "counts", "metadata", "expires_at", "next_poll_at")
  values (
    record_ai_batch.tenant,
    case when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then (v_fields ->> 'user_id')::uuid else auth.uid() end,
    record_ai_batch.provider,
    record_ai_batch.reference,
    coalesce(v_fields ->> 'status', 'pending'),
    v_fields ->> 'raw_status',
    coalesce((v_fields ->> 'item_count')::integer, 0),
    coalesce(v_fields -> 'counts', '{}'),
    coalesce(v_fields -> 'metadata', '{}'),
    (v_fields ->> 'expires_at')::timestamptz,
    now() + interval '60 seconds'
  )
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'user_id', v_row."user_id", 'provider', v_row."provider", 'reference', v_row."reference", 'status', v_row."status", 'raw_status', v_row."raw_status", 'item_count', v_row."item_count", 'counts', v_row."counts", 'error', v_row."error", 'metadata', v_row."metadata", 'results_saved', v_row."results_saved", 'polls', v_row."polls", 'next_poll_at', v_row."next_poll_at", 'expires_at', v_row."expires_at", 'completed_at', v_row."completed_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_usage (
  tenant          uuid,
  meter           text,
  quantity        numeric DEFAULT 1,
  idempotency_key text    DEFAULT NULL::text,
  source          text    DEFAULT NULL::text,
  metadata        jsonb   DEFAULT NULL::jsonb,
  actor           uuid    DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  today date := (now() at time zone 'utc')::date;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', tenant, 'usage.record'), false)) then
    raise exception 'Not allowed to record usage in this tenant' using errcode = '42501', hint = 'USAGE_FORBIDDEN';
  end if;
  if quantity is null or quantity < 0 then
    raise exception 'quantity must be zero or more' using errcode = '22023', hint = 'USAGE_QUANTITY';
  end if;
  if idempotency_key is not null then
    insert into "better_supabase"."usage_events" ("organization_id", "meter", "idempotency_key", "quantity")
    values (tenant, meter, idempotency_key, quantity)
    on conflict do nothing;
    if not found then
      return jsonb_build_object('recorded', false, 'used', "better_supabase"."usage_used"(tenant, meter, coalesce((select q.period from "better_supabase"."usage_quota"(tenant, meter) q), 'month')), 'today', "better_supabase"."usage_used"(tenant, meter, 'day'));
    end if;
  end if;
  insert into "better_supabase"."usage_counters" as c ("organization_id", "meter", "day", "value")
  values (tenant, meter, today, quantity)
  on conflict ("organization_id", "meter", "day") do update
    set "value" = c."value" + excluded."value", "updated_at" = now();
  return jsonb_build_object('recorded', true, 'used', "better_supabase"."usage_used"(tenant, meter, coalesce((select q.period from "better_supabase"."usage_quota"(tenant, meter) q), 'month')), 'today', "better_supabase"."usage_used"(tenant, meter, 'day'));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.register_push_device (
  token       text,
  platform    text,
  provider    text DEFAULT 'expo'::text,
  device_name text DEFAULT NULL::text,
  app_version text DEFAULT NULL::text
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_user uuid := auth.uid();
  v_id uuid;
  v_new boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_user is null then
    raise exception 'Sign in first' using errcode = '42501', hint = 'PUSH_FORBIDDEN';
  end if;
  if register_push_device.platform is null or register_push_device.platform not in ('ios', 'android', 'web') then
    raise exception 'Unknown push platform %', register_push_device.platform using errcode = '22023', hint = 'PUSH_PLATFORM';
  end if;
  if register_push_device.provider is null or register_push_device.provider not in ('expo', 'fcm', 'apns', 'webpush') then
    raise exception 'Unknown push provider %', register_push_device.provider using errcode = '22023', hint = 'PUSH_PROVIDER';
  end if;
  if register_push_device.token is null or length(register_push_device.token) not between 1 and 4096 then
    raise exception 'A push token is 1 to 4096 characters' using errcode = '22023', hint = 'PUSH_TOKEN';
  end if;
  insert into "better_supabase"."push_devices" as x ("user_id", "token", "platform", "provider", "device_name", "app_version")
  values (
    v_user,
    register_push_device.token,
    register_push_device.platform,
    register_push_device.provider,
    left(register_push_device.device_name, 200),
    left(register_push_device.app_version, 50)
  )
  on conflict ("token") do update set
    "user_id" = excluded."user_id",
    "platform" = excluded."platform",
    "provider" = excluded."provider",
    "device_name" = coalesce(excluded."device_name", x."device_name"),
    "app_version" = coalesce(excluded."app_version", x."app_version"),
    "last_seen_at" = now()
  returning x."id", (x.xmax = 0) into v_id, v_new;
  if v_new then
    perform better_supabase.audit_event(
    event_type => 'push.device_registered',
    category => 'security',
    target_type => 'push_device',
    record_id => v_id::text,
    metadata => jsonb_build_object('deviceId', v_id::text, 'userId', v_user::text, 'platform', register_push_device.platform, 'provider', register_push_device.provider)
  );
  end if;
  return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.remove_member (
  organization uuid,
  member       uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  current_role_value text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if member = auth.uid() then
    raise exception 'Leave the organization instead' using errcode = '22023', hint = 'ORGANIZATION_SELF';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), organization, 'members.remove'), false)) then
    raise exception 'Not allowed to remove members' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  select m."role"::text into current_role_value from "public"."memberships" m where m."organization_id" = organization and m."user_id" = member;
  if not found then
    raise exception 'Not a member' using errcode = 'P0002', hint = 'ORGANIZATION_NOT_MEMBER';
  end if;
  if not better_supabase.can_assign(organization, current_role_value) then
    raise exception 'That member''s role is above your own' using errcode = '42501', hint = 'ORGANIZATION_ROLE_CEILING';
  end if;
  delete from "public"."memberships" where "organization_id" = organization and "user_id" = member;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_member_change"(uuid, uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text)', v_hook::oid::regproc)
        using organization, member, 'removed';
    end if;
  end;
  perform better_supabase.audit_event(
    event_type => 'organization.member_removed',
    category => 'membership',
    target_type => 'user',
    record_id => member::text,
    tenant => (organization)::uuid,
    metadata => jsonb_build_object('organizationId', organization::text, 'userId', member)
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.remove_team_member (
  team   uuid,
  member uuid
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
  select "tenant_id" into v_tenant from "better_supabase"."teams" where "id" = remove_team_member.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  delete from "better_supabase"."team_members"
  where "team_id" = remove_team_member.team and "user_id" = remove_team_member.member;
  perform better_supabase.audit_event(
    event_type => 'team_member.removed',
    category => 'membership',
    target_type => 'team',
    record_id => (remove_team_member.team)::text,
    tenant => (v_tenant)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'id', remove_team_member.team, 'userId', remove_team_member.member)
  );
  return found;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.remove_workflow_alert (
  alert uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from "better_supabase"."workflow_alerts" x
  using "better_supabase"."workflow_definitions" y
  where x."id" = alert and y."id" = x."definition_id"
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (y."tenant_id" is not null and coalesce(better_supabase.can('tenant', y."tenant_id", 'workflow.admin'), false)));
  return found;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.remove_workflow_credential (
  credential uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."workflow_credentials"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from "better_supabase"."workflow_credentials" x
  where x."id" = credential and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (x."tenant_id" is not null and coalesce(better_supabase.can('tenant', x."tenant_id", 'workflow.admin'), false)))
  returning * into v_row;
  if not found then
    return null;
  end if;
  return jsonb_build_object(
    'id', v_row."id",
    'tenant', v_row."tenant_id",
    'kind', v_row."kind",
    'name', v_row."name",
    'ref', v_row."credential_ref",
    'scopes', to_jsonb(v_row."scopes"),
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at"
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.remove_workflow_definition (
  definition uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from "better_supabase"."workflow_definitions" x
  where x."id" = definition and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (x."tenant_id" is not null and coalesce(better_supabase.can('tenant', x."tenant_id", 'workflow.admin'), false)));
  return found;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.remove_workflow_schedule (
  schedule uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from "better_supabase"."workflow_schedules" x
  where x."id" = schedule
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (x."tenant_id" is not null and coalesce(better_supabase.can('tenant', x."tenant_id", 'workflow.admin'), false)));
  return found;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.remove_workflow_trigger (
  trigger uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from "better_supabase"."workflow_triggers" x
  using "better_supabase"."workflow_definitions" y
  where x."id" = trigger and y."id" = x."definition_id"
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (y."tenant_id" is not null and coalesce(better_supabase.can('tenant', y."tenant_id", 'workflow.edit'), false)));
  return found;
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
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_chat."owner_id" = (select auth.uid())) then
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

CREATE OR REPLACE FUNCTION better_supabase.request_workflow_cancel (
  run text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_run "better_supabase"."workflow_runs"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_run from "better_supabase"."workflow_runs" x
  where (x."id"::text = request_workflow_cancel.run or x."external_id" = request_workflow_cancel.run)
  order by x."id"::text = request_workflow_cancel.run desc
  limit 1
  for update;
  if not found then
    return null;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
    or v_run."actor_id" = (select auth.uid())
    or (v_run."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_run."tenant_id", 'workflow.admin'), false))) then
    raise exception 'You may not cancel this run' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  if v_run."status" in ('completed', 'failed', 'cancelled') then
    return jsonb_build_object(
    'id', v_run."id",
    'engine', v_run."engine",
    'externalId', v_run."external_id",
    'definition', v_run."definition",
    'tenant', v_run."tenant_id",
    'actor', v_run."actor_id",
    'status', v_run."status",
    'attributes', v_run."attributes",
    'error', v_run."error",
    'createdAt', v_run."created_at",
    'updatedAt', v_run."updated_at",
    'startedAt', v_run."started_at",
    'completedAt', v_run."completed_at",
    'cancelRequestedAt', v_run."cancel_requested_at"
  );
  end if;
  update "better_supabase"."workflow_runs" set "cancel_requested_at" = coalesce("cancel_requested_at", now()), "updated_at" = now()
  where "id" = v_run."id"
  returning * into v_run;
  return jsonb_build_object(
    'id', v_run."id",
    'engine', v_run."engine",
    'externalId', v_run."external_id",
    'definition', v_run."definition",
    'tenant', v_run."tenant_id",
    'actor', v_run."actor_id",
    'status', v_run."status",
    'attributes', v_run."attributes",
    'error', v_run."error",
    'createdAt', v_run."created_at",
    'updatedAt', v_run."updated_at",
    'startedAt', v_run."started_at",
    'completedAt', v_run."completed_at",
    'cancelRequestedAt', v_run."cancel_requested_at"
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.resend_invitation (
  invitation_id uuid,
  valid_for     interval DEFAULT '7 days'::interval
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  token text := encode(extensions.gen_random_bytes(24), 'hex');
  updated "better_supabase"."invitations";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if valid_for is null or valid_for <= interval '0' or valid_for > '30 days'::interval then
    raise exception 'An invitation is valid for at most %', '30 days' using errcode = '22023', hint = 'INVITATION_VALIDITY';
  end if;
  update "better_supabase"."invitations" i
  set "token_hash" = encode(extensions.digest(token, 'sha256'), 'hex'),
    "expires_at" = now() + valid_for
  where i."id" = invitation_id and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), i."organization_id", 'members.invite'), false))
  returning * into updated;
  if updated."id" is null then
    raise exception 'No open invitation %', invitation_id using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  perform better_supabase.audit_event(
    event_type => 'invitation.resent',
    category => 'membership',
    target_type => 'invitation',
    record_id => updated."id"::text,
    tenant => (updated."organization_id")::uuid,
    metadata => jsonb_build_object('invitationId', updated."id", 'organizationId', updated."organization_id"::text, 'email', updated."email")
  );
  return (jsonb_build_object(
    'id', updated."id",
    'tenant', updated."organization_id",
    'email', updated."email",
    'role', updated."role",
    'expires_at', updated."expires_at",
    'created_at', updated."created_at",
    'invited_by', updated."invited_by",
    'organization', (select jsonb_build_object('id', o."id", 'name', o."name")
      from "public"."organizations" o where o."id" = updated."organization_id"),
    'prefill', '{}'::jsonb,
    'inviter', (select jsonb_build_object('id', pr."id", 'username', pr."username", 'fullName', pr."full_name", 'firstName', pr."first_name", 'lastName', pr."last_name", 'avatar', pr."avatar_url")
      from "better_supabase"."profiles" pr where pr."id" = updated."invited_by"),
    'token', token
  ) || "better_supabase"."invitation_extra"(updated."id"));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.reserve_ai_file (
  tenant     uuid,
  filename   text,
  media_type text,
  byte_size  bigint,
  chat_id    uuid   DEFAULT NULL::uuid,
  project_id uuid   DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."ai_files"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null or not coalesce(better_supabase.can('tenant', reserve_ai_file.tenant, 'ai.create'), false) then
    raise exception 'you may not upload files here' using errcode = '42501', hint = 'AI_FILE_FORBIDDEN';
  end if;
  if byte_size < 0 or byte_size > 52428800 then
    raise exception 'files are limited to % bytes', 52428800 using errcode = '22023', hint = 'AI_FILE_TOO_LARGE';
  end if;
  insert into "better_supabase"."ai_files" ("organization_id", "owner_id", "chat_id", "project_id", "bucket", "filename", "media_type", "byte_size")
  values (reserve_ai_file.tenant, auth.uid(), reserve_ai_file.chat_id, reserve_ai_file.project_id, 'ai-files', reserve_ai_file.filename, lower(reserve_ai_file.media_type), reserve_ai_file.byte_size)
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'chat_id', v_row."chat_id", 'project_id', v_row."project_id", 'bucket', v_row."bucket", 'path', v_row."path", 'media_type', v_row."media_type", 'filename', v_row."filename", 'byte_size', v_row."byte_size", 'sha256', v_row."sha256", 'status', v_row."status", 'source', v_row."source", 'created_at', v_row."created_at", 'uploaded_at', v_row."uploaded_at", 'expires_at', v_row."expires_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.reset_onboarding_step (
  checklist text,
  step      text,
  tenant    uuid DEFAULT NULL::uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_scope text;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  v_scope := (select s.scope from (values ('getting-started', 'customer', 'organization'), ('getting-started', 'invite', 'organization'), ('getting-started', 'api-key', 'organization'), ('getting-started', 'plan', 'organization')) as s(checklist, step, scope) where s.checklist = reset_onboarding_step.checklist and (reset_onboarding_step.step is null or s.step = reset_onboarding_step.step) limit 1);
  if v_scope is null then
    raise exception 'Unknown onboarding step %.%', reset_onboarding_step.checklist, coalesce(reset_onboarding_step.step, '*') using errcode = '22023', hint = 'ONBOARDING_STEP_UNKNOWN';
  end if;
  if v_scope = 'organization' then
    if reset_onboarding_step.tenant is null then
      raise exception 'Checklist % belongs to an organization', reset_onboarding_step.checklist using errcode = '22023', hint = 'ONBOARDING_SCOPE';
    end if;
  elsif reset_onboarding_step.tenant is not null then
    raise exception 'Checklist % belongs to a user', reset_onboarding_step.checklist using errcode = '22023', hint = 'ONBOARDING_SCOPE';
  elsif auth.uid() is null then
    raise exception 'Sign in first' using errcode = '42501', hint = 'ONBOARDING_FORBIDDEN';
  end if;
  if v_scope = 'organization' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', reset_onboarding_step.tenant, 'onboarding.complete'), false)) then
    raise exception 'You may not change this organization''s onboarding' using errcode = '42501', hint = 'ONBOARDING_FORBIDDEN';
  end if;
  delete from "better_supabase"."onboarding_progress" x
  where x."step" = reset_onboarding_step.step and x."checklist" = reset_onboarding_step.checklist
      and (case when v_scope = 'organization' then x."organization_id" = reset_onboarding_step.tenant else x."user_id" = auth.uid() end);
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.resolve_ai_suggestion (
  suggestion_id uuid,
  accepted      boolean
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."ai_suggestions"%rowtype;
  v_doc "better_supabase"."ai_documents"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."ai_suggestions" x where x."id" = resolve_ai_suggestion.suggestion_id for update;
  if found then
    select * into v_doc from "better_supabase"."ai_documents" x where x."id" = v_row."document_id";
  end if;
  if v_doc."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_doc."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_doc."organization_id", 'ai.admin'), false)) then
    raise exception 'suggestion % not found', suggestion_id using errcode = 'P0002', hint = 'AI_SUGGESTION_NOT_FOUND';
  end if;
  update "better_supabase"."ai_suggestions" x set "resolved_at" = now(), "accepted" = resolve_ai_suggestion.accepted
  where x."id" = v_row."id"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'document_id', v_row."document_id", 'version', v_row."version", 'original_text', v_row."original_text", 'suggested_text', v_row."suggested_text", 'description', v_row."description", 'created_by', v_row."created_by", 'created_at', v_row."created_at", 'resolved_at', v_row."resolved_at", 'accepted', v_row."accepted");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.resolve_notifications (
  type         text,
  subject_type text,
  subject_id   text,
  tenant       uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_changed jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) or coalesce(better_supabase.member_can(auth.uid(), resolve_notifications.tenant, 'notifications.send'), false)) then
    raise exception 'Not allowed to resolve notifications here' using errcode = '42501', hint = 'NOTIFICATION_FORBIDDEN';
  end if;
  with rc as (
    update "better_supabase"."notification_recipients" rc
    set "resolved_at" = now(), "read_at" = coalesce(rc."read_at", now())
    from "better_supabase"."notification_events" ev
    where ev."id" = rc."event_id"
      and ev."type" = resolve_notifications.type
      and ev."subject_type" = resolve_notifications.subject_type
      and ev."subject_id" = resolve_notifications.subject_id
      and ev."organization_id" is not distinct from resolve_notifications.tenant
      and rc."resolved_at" is null
      and rc."dismissed_at" is null
    returning rc.*
  )
  select jsonb_build_object(
    'count', count(*),
    'items', coalesce(jsonb_agg(jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."organization_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'priority', ev."priority", 'resolved_at', rc."resolved_at") order by rc."created_at" desc, rc."id" desc) filter (where rc."user_id" = auth.uid()), '[]')
  )
  from rc
  join "better_supabase"."notification_events" ev on ev."id" = rc."event_id" into v_changed;
  return v_changed;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.revoke_ai_chat_share (
  id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_chat_id uuid;
  v_chat "better_supabase"."ai_chats";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "better_supabase"."ai_chat_shares" x set "revoked_at" = now()
  where x."id" = revoke_ai_chat_share.id
    and x."revoked_at" is null
    and (
      coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
      or x."created_by" = (select auth.uid())
      or exists (select 1 from "better_supabase"."ai_chats" c where c."id" = x."chat_id" and c."owner_id" = (select auth.uid()))
    )
  returning x."chat_id" into v_chat_id;
  if v_chat_id is null then
    return false;
  end if;
  select * into v_chat from "better_supabase"."ai_chats" c where c."id" = v_chat_id;
  perform better_supabase.audit_event(
    event_type => 'ai_chat.share_revoked',
    category => 'ai',
    target_type => 'ai_chat_share',
    record_id => revoke_ai_chat_share.id::text,
    tenant => (v_chat."organization_id")::uuid,
    metadata => jsonb_build_object('chatId', v_chat."id", 'shareId', revoke_ai_chat_share.id, 'organizationId', v_chat."organization_id"::text, 'ownerId', v_chat."owner_id")
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.revoke_api_key (
  key uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  found "better_supabase"."api_keys";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into found from "better_supabase"."api_keys" k where k."id" = revoke_api_key.key;
  if found."id" is null or not ((found."organization_id" is not null and coalesce(better_supabase.can('tenant', found."organization_id", 'api_keys.manage'), false)) or coalesce(found."user_id" = auth.uid(), false) or coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'API key not found' using errcode = 'P0002', hint = 'API_KEY_NOT_FOUND';
  end if;
  update "better_supabase"."api_keys" k set "revoked_at" = now()
  where k."id" = found."id" and (k."revoked_at" is null or k."revoked_at" > now());
  perform better_supabase.audit_event(
    event_type => 'api_key.revoked',
    category => 'security',
    target_type => 'api_key',
    record_id => found."id"::text,
    target_label => found."name",
    tenant => (found."organization_id")::uuid,
    metadata => jsonb_build_object('keyId', found."id", 'organizationId', found."organization_id"::text, 'userId', found."user_id", 'name', found."name", 'publicId', found."public_id")
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.revoke_connector_grant (
  id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."connector_grants"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "better_supabase"."connector_grants" y set "revoked_at" = now()
  where y."id" = revoke_connector_grant.id and y."revoked_at" is null
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or y."user_id" = auth.uid())
  returning * into v_row;
  if not found then
    return null;
  end if;
  delete from "better_supabase"."connector_sessions" z where z."server_id" = v_row."server_id" and z."user_id" = v_row."user_id";
  perform better_supabase.audit_event(
    event_type => 'connector_grant.revoked',
    category => 'integration',
    target_type => 'connector_grant',
    record_id => v_row."id"::text,
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'grantId', v_row."id", 'serverId', v_row."server_id", 'userId', v_row."user_id")
  );
  return jsonb_build_object('id', v_row."id", 'user_id', v_row."user_id", 'server_id', v_row."server_id", 'organization_id', v_row."organization_id", 'credential_ref', v_row."credential_ref", 'scopes', v_row."scopes", 'expires_at', v_row."expires_at", 'granted_at', v_row."granted_at", 'revoked_at', v_row."revoked_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.revoke_invitation (
  invitation_id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  tenant text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "better_supabase"."invitations" i set "revoked_at" = now() where i."id" = invitation_id and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), i."organization_id", 'members.invite'), false)) and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
  returning i."organization_id"::text into tenant;
  if found then
    perform better_supabase.audit_event(
    event_type => 'invitation.revoked',
    category => 'membership',
    target_type => 'invitation',
    record_id => invitation_id::text,
    tenant => (tenant)::uuid,
    metadata => jsonb_build_object('invitationId', invitation_id, 'organizationId', tenant)
  );
    return true;
  end if;
  return false;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.rollback_ai_document (
  document_id uuid,
  version     integer
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."ai_documents"%rowtype;
  v_old "better_supabase"."ai_document_versions"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."ai_documents" x where x."id" = rollback_ai_document.document_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai.admin'), false)) then
    raise exception 'document % not found', document_id using errcode = 'P0002', hint = 'AI_DOCUMENT_NOT_FOUND';
  end if;
  select * into v_old from "better_supabase"."ai_document_versions" x where x."document_id" = v_row."id" and x."version" = rollback_ai_document.version;
  if not found then
    raise exception 'document % has no version %', document_id, rollback_ai_document.version using errcode = 'P0002', hint = 'AI_DOCUMENT_VERSION_NOT_FOUND';
  end if;
  insert into "better_supabase"."ai_document_versions" ("document_id", "version", "content", "storage_path", "created_by_message_id", "created_by")
  values (v_row."id", v_row."current_version" + 1, v_old."content", v_old."storage_path", null, auth.uid());
  update "better_supabase"."ai_documents" x set "current_version" = v_row."current_version" + 1, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'chat_id', v_row."chat_id", 'kind', v_row."kind", 'title', v_row."title", 'current_version', v_row."current_version", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.rotate_api_key (
  key         uuid,
  public_id   text,
  secret_hash text,
  grace       interval DEFAULT '1 day'::interval
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  old "better_supabase"."api_keys";
  created "better_supabase"."api_keys";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into old from "better_supabase"."api_keys" k where k."id" = rotate_api_key.key for update;
  if old."id" is null or not ((old."organization_id" is not null and coalesce(better_supabase.can('tenant', old."organization_id", 'api_keys.manage'), false)) or coalesce(old."user_id" = auth.uid(), false) or coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'API key not found' using errcode = 'P0002', hint = 'API_KEY_NOT_FOUND';
  end if;
  if old."revoked_at" is not null and old."revoked_at" <= now() then
    raise exception 'A revoked API key cannot be rotated' using errcode = '22023', hint = 'API_KEY_REVOKED';
  end if;
  if old."expires_at" is not null and old."expires_at" <= now() then
    raise exception 'An expired API key cannot be rotated' using errcode = '22023', hint = 'API_KEY_EXPIRED';
  end if;
  if grace is null or grace < interval '0' then
    raise exception 'grace must be zero or more' using errcode = '22023', hint = 'API_KEY_GRACE';
  end if;
  insert into "better_supabase"."api_keys" ("organization_id", "user_id", "name", "prefix", "public_id", "secret_hash", "scopes", "rate_limit", "expires_at", "rotated_from")
  values (old."organization_id", old."user_id", old."name", old."prefix", rotate_api_key.public_id, rotate_api_key.secret_hash, old."scopes", old."rate_limit", old."expires_at", old."id")
  returning * into created;
  update "better_supabase"."api_keys" k set "revoked_at" = now() + grace where k."id" = old."id";
  perform better_supabase.audit_event(
    event_type => 'api_key.rotated',
    category => 'security',
    target_type => 'api_key',
    record_id => created."id"::text,
    target_label => created."name",
    tenant => (created."organization_id")::uuid,
    metadata => jsonb_build_object('keyId', created."id", 'organizationId', created."organization_id"::text, 'userId', created."user_id", 'name', created."name", 'publicId', created."public_id", 'previousKeyId', old."id")
  );
  return jsonb_build_object(
    'id', created."id",
    'organization_id', created."organization_id",
    'user_id', created."user_id",
    'name', created."name",
    'prefix', created."prefix",
    'public_id', created."public_id",
    'scopes', to_jsonb(created."scopes"),
    'rate_limit', created."rate_limit",
    'expires_at', created."expires_at",
    'last_used_at', created."last_used_at",
    'revoked_at', created."revoked_at",
    'rotated_from', created."rotated_from",
    'created_by', created."created_by",
    'created_at', created."created_at",
    'state', case
      when created."revoked_at" is not null and created."revoked_at" <= now() then 'revoked'
      when created."expires_at" is not null and created."expires_at" <= now() then 'expired'
      when created."revoked_at" is not null then 'grace'
      else 'active'
    end,
    'successor_id', (select s."id" from "better_supabase"."api_keys" s where s."rotated_from" = created."id" order by s."created_at" desc limit 1)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.rotate_workflow_webhook_token (
  trigger uuid
)
  RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_tenant uuid;
  v_kind text;
  v_token text := 'wfh_' || encode(extensions.gen_random_bytes(24), 'hex');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select y."tenant_id", x."kind" into v_tenant, v_kind
  from "better_supabase"."workflow_triggers" x join "better_supabase"."workflow_definitions" y on y."id" = x."definition_id"
  where x."id" = trigger;
  if not found then
    raise exception 'No such trigger' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'workflow.edit'), false))) then
    raise exception 'You may not edit this workflow' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  if v_kind <> 'webhook' then
    raise exception 'Only webhook triggers have tokens' using errcode = '22023', hint = 'WORKFLOW_TRIGGER_KIND';
  end if;
  delete from "better_supabase"."workflow_webhook_tokens" x where x."trigger_id" = trigger;
  insert into "better_supabase"."workflow_webhook_tokens" ("token_hash", "trigger_id")
  values (extensions.digest(v_token, 'sha256'), trigger);
  return v_token;
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
    if auth.uid() is null or not coalesce(better_supabase.can('tenant', save_agent.tenant, 'ai.create'), false) then
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
    if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai.moderate'), false)) then
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
  perform better_supabase.audit_event(
    event_type => 'agent.saved',
    category => 'ai',
    target_type => 'agent',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'agentId', v_row."id", 'slug', v_row."slug")
  );
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
exception
  when unique_violation then
    raise exception 'an agent with slug % exists', save_agent.fields ->> 'slug' using errcode = '23505', hint = 'AGENT_SLUG_TAKEN';
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_ai_project (
  id     uuid,
  tenant uuid,
  fields jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_fields jsonb := coalesce(save_ai_project.fields, '{}'::jsonb);
  v_row "better_supabase"."ai_projects";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if save_ai_project.id is null then
    if auth.uid() is null or not coalesce(better_supabase.can('tenant', save_ai_project.tenant, 'ai_chat.create'), false) then
      raise exception 'You may not create projects here' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
    end if;
    insert into "better_supabase"."ai_projects" ("organization_id", "owner_id", "name", "instructions", "default_model", "pinned")
    values (
      save_ai_project.tenant, auth.uid(), v_fields ->> 'name', coalesce(v_fields ->> 'instructions', ''),
      v_fields ->> 'default_model', coalesce((v_fields ->> 'pinned')::boolean, false)
    )
    returning * into v_row;
    return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'name', v_row."name", 'instructions', v_row."instructions", 'default_model', v_row."default_model", 'pinned', v_row."pinned", 'archived_at', v_row."archived_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
  end if;
  update "better_supabase"."ai_projects" x set
    "name" = coalesce(v_fields ->> 'name', x."name"),
    "instructions" = case when v_fields ? 'instructions' then coalesce(v_fields ->> 'instructions', '') else x."instructions" end,
    "default_model" = case when v_fields ? 'default_model' then v_fields ->> 'default_model' else x."default_model" end,
    "pinned" = case when v_fields ? 'pinned' then coalesce((v_fields ->> 'pinned')::boolean, false) else x."pinned" end,
    "archived_at" = case
      when not v_fields ? 'archived' then x."archived_at"
      when coalesce((v_fields ->> 'archived')::boolean, false) then coalesce(x."archived_at", now())
    end,
    "updated_at" = now()
  where x."id" = save_ai_project.id and x."owner_id" = (select auth.uid())
  returning * into v_row;
  if not found then
    raise exception 'No project %', save_ai_project.id using errcode = 'P0002', hint = 'AI_PROJECT_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'name', v_row."name", 'instructions', v_row."instructions", 'default_model', v_row."default_model", 'pinned', v_row."pinned", 'archived_at', v_row."archived_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
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

CREATE OR REPLACE FUNCTION better_supabase.save_ai_task (
  tenant      uuid,
  id          uuid                     DEFAULT NULL::uuid,
  fields      jsonb                    DEFAULT '{}'::jsonb,
  next_run_at timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid := save_ai_task.id;
  v_row "better_supabase"."ai_scheduled_tasks"%rowtype;
  v_service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
  v_chat uuid;
  v_agent uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(save_ai_task.fields) is distinct from 'object' then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'AI_TASK_INVALID';
  end if;
  if save_ai_task.fields ? 'timezone' then
    begin
      perform now() at time zone (save_ai_task.fields ->> 'timezone');
    exception when others then
      raise exception '% is not a time zone', save_ai_task.fields ->> 'timezone' using errcode = '22023', hint = 'AI_TASK_INVALID';
    end;
  end if;
  if v_id is null then
    if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_ai_task.tenant, 'ai.create'), false)) or auth.uid() is null then
      raise exception 'you may not schedule tasks here' using errcode = '42501', hint = 'AI_TASK_FORBIDDEN';
    end if;
    insert into "better_supabase"."ai_scheduled_tasks" ("organization_id", "user_id", "title", "prompt", "cron")
    values (save_ai_task.tenant, auth.uid(), save_ai_task.fields ->> 'title', save_ai_task.fields ->> 'prompt', save_ai_task.fields ->> 'cron')
    returning * into v_row;
  else
    select * into v_row from "better_supabase"."ai_scheduled_tasks" x where x."id" = v_id and x."organization_id" = save_ai_task.tenant for update;
    if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."user_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai.admin'), false)) then
      raise exception 'task % not found', v_id using errcode = 'P0002', hint = 'AI_TASK_NOT_FOUND';
    end if;
  end if;
  v_chat := (save_ai_task.fields ->> 'chat_id')::uuid;
  if v_chat is not null and not v_service and not exists (select 1 from "better_supabase"."ai_chats" c where c."id" = v_chat and c."owner_id" = v_row."user_id" and c."organization_id" = v_row."organization_id")
  then
    raise exception 'chat % is not a chat of this task''s user', v_chat using errcode = '42501', hint = 'AI_TASK_CHAT_FORBIDDEN';
  end if;
  v_agent := (save_ai_task.fields ->> 'agent_id')::uuid;
  if v_agent is not null and not v_service and not exists (select 1 from "better_supabase"."agents" g where g."id" = v_agent and g."organization_id" = v_row."organization_id" and (g."owner_id" = v_row."user_id" or g."published_at" is not null))
  then
    raise exception 'agent % is not an agent this task''s user may use', v_agent using errcode = '42501', hint = 'AI_TASK_AGENT_FORBIDDEN';
  end if;
  update "better_supabase"."ai_scheduled_tasks" x set
    "title" = coalesce(save_ai_task.fields ->> 'title', x."title"),
    "prompt" = coalesce(save_ai_task.fields ->> 'prompt', x."prompt"),
    "cron" = coalesce(save_ai_task.fields ->> 'cron', x."cron"),
    "timezone" = coalesce(save_ai_task.fields ->> 'timezone', x."timezone"),
    "chat_id" = case when save_ai_task.fields ? 'chat_id' then (save_ai_task.fields ->> 'chat_id')::uuid else x."chat_id" end,
    "agent_id" = case when save_ai_task.fields ? 'agent_id' then (save_ai_task.fields ->> 'agent_id')::uuid else x."agent_id" end,
    "enabled" = coalesce((save_ai_task.fields ->> 'enabled')::boolean, x."enabled"),
    "next_run_at" = case
      when (save_ai_task.fields ->> 'enabled')::boolean is false then null
      when v_service and (save_ai_task.next_run_at is not null or save_ai_task.fields ? 'cron' or save_ai_task.fields ? 'timezone') then save_ai_task.next_run_at
      when save_ai_task.id is null or save_ai_task.fields ? 'cron' or save_ai_task.fields ? 'timezone' then null
      else x."next_run_at" end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'user_id', v_row."user_id", 'chat_id', v_row."chat_id", 'agent_id', v_row."agent_id", 'title', v_row."title", 'prompt', v_row."prompt", 'cron', v_row."cron", 'timezone', v_row."timezone", 'enabled', v_row."enabled", 'next_run_at', v_row."next_run_at", 'last_run_at', v_row."last_run_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.is_platform('announcements.manage'), false)) then
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
  perform better_supabase.audit_event(
    event_type => 'announcement.saved',
    category => 'configuration',
    target_type => 'announcement',
    record_id => v_row."id"::text,
    metadata => jsonb_build_object('announcementId', v_row."id")
  );
  return to_jsonb(v_row);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_connector_server.tenant, 'ai.admin'), false)) then
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
  perform better_supabase.audit_event(
    event_type => 'connector.saved',
    category => 'integration',
    target_type => 'connector',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'serverId', v_row."id", 'name', v_row."name")
  );
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'name', v_row."name", 'url', v_row."url", 'transport', v_row."transport", 'auth_type', v_row."auth_type", 'credential_ref', v_row."credential_ref", 'scopes', v_row."scopes", 'client_metadata', v_row."client_metadata", 'enabled', v_row."enabled", 'created_by', v_row."created_by", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_connector_session (
  server_id         uuid,
  chat_key          text  DEFAULT ''::text,
  session_id        text  DEFAULT NULL::text,
  initialize_result jsonb DEFAULT NULL::jsonb
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null then
    return false;
  end if;
  if save_connector_session.session_id is null and save_connector_session.initialize_result is null then
    delete from "better_supabase"."connector_sessions" z where z."server_id" = save_connector_session.server_id and z."user_id" = auth.uid()
      and z."chat_key" = coalesce(save_connector_session.chat_key, '');
    return true;
  end if;
  if not exists (select 1 from "better_supabase"."connector_grants" y where y."server_id" = save_connector_session.server_id and y."user_id" = auth.uid() and y."revoked_at" is null)
    and not exists (select 1 from "better_supabase"."connector_servers" x where x."id" = save_connector_session.server_id and x."auth_type" <> 'oauth' and coalesce(better_supabase.can('tenant', x."organization_id", 'ai.create'), false)) then
    return false;
  end if;
  insert into "better_supabase"."connector_sessions" ("server_id", "user_id", "chat_key", "session_id", "initialize_result", "expires_at")
  values (save_connector_session.server_id, auth.uid(), coalesce(save_connector_session.chat_key, ''), save_connector_session.session_id,
    save_connector_session.initialize_result, now() + interval '1 hour')
  on conflict ("server_id", "user_id", "chat_key") do update set
    "session_id" = excluded."session_id", "initialize_result" = excluded."initialize_result",
    "last_used_at" = now(), "expires_at" = excluded."expires_at";
  return true;
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.is_platform('flags.manage'), false)) then
    raise exception 'Not allowed to manage feature flags' using errcode = '42501', hint = 'FLAGS_FORBIDDEN';
  end if;
  insert into "better_supabase"."flags" as x ("key", "type", "description", "variants", "default_variant", "enabled", "rules", "rollout_percentage", "rollout_variant")
  values (
    save_flag.key,
    coalesce(d ->> 'type', 'boolean'),
    d ->> 'description',
    coalesce(d -> 'variants', '{"on": true, "off": false}'::jsonb),
    coalesce(d ->> 'default_variant', 'off'),
    coalesce((d ->> 'enabled')::boolean, true),
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
    "rules" = case when d ? 'rules' then excluded."rules" else x."rules" end,
    "rollout_percentage" = case when d ? 'rollout_percentage' then excluded."rollout_percentage" else x."rollout_percentage" end,
    "rollout_variant" = case when d ? 'rollout_variant' then excluded."rollout_variant" else x."rollout_variant" end,
    "updated_at" = now();
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

CREATE OR REPLACE FUNCTION better_supabase.save_workflow_alert (
  definition uuid,
  on_event   text,
  channel    jsonb    DEFAULT '{}'::jsonb,
  threshold  interval DEFAULT NULL::interval,
  alert      uuid     DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_tenant uuid;
  v_row "better_supabase"."workflow_alerts"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."workflow_definitions" x where x."id" = definition;
  if not found then
    raise exception 'No such workflow' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'workflow.admin'), false))) then
    raise exception 'You may not manage alerts for this workflow' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  if alert is null then
    insert into "better_supabase"."workflow_alerts" ("definition_id", "on_event", "threshold", "channel", "created_by")
    values (definition, on_event, threshold, coalesce(channel, '{}'::jsonb), (select auth.uid()))
    returning * into v_row;
  else
    update "better_supabase"."workflow_alerts" x set "on_event" = on_event, "threshold" = threshold, "channel" = coalesce(channel, '{}'::jsonb)
    where x."id" = alert and x."definition_id" = definition
    returning * into v_row;
    if not found then
      raise exception 'No such alert' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
    end if;
  end if;
  return jsonb_build_object(
    'id', v_row."id",
    'definition', v_row."definition_id",
    'onEvent', v_row."on_event",
    'threshold', extract(epoch from v_row."threshold"),
    'channel', v_row."channel",
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at"
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_workflow_credential (
  tenant uuid,
  kind   text,
  name   text,
  ref    jsonb,
  scopes text[] DEFAULT '{}'::text[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."workflow_credentials"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (tenant is not null and coalesce(better_supabase.can('tenant', tenant, 'workflow.admin'), false))) then
    raise exception 'You may not manage workflow credentials here' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and save_workflow_credential.ref is not null and jsonb_typeof(save_workflow_credential.ref) <> 'null'
    and (jsonb_typeof(save_workflow_credential.ref -> 'tenant') is distinct from 'string' or (save_workflow_credential.ref ->> 'tenant') is distinct from (save_workflow_credential.tenant)::text) then
    raise exception 'credential_ref must carry the tenant % that owns it', save_workflow_credential.tenant
      using errcode = '42501', hint = 'CREDENTIAL_REF_FOREIGN';
  end if;
  insert into "better_supabase"."workflow_credentials" as x ("tenant_id", "kind", "name", "credential_ref", "scopes", "created_by")
  values (tenant, kind, name, ref, coalesce(scopes, '{}'), (select auth.uid()))
  on conflict on constraint workflow_credentials_tenant_name_key do update set
    "kind" = excluded."kind",
    "credential_ref" = excluded."credential_ref",
    "scopes" = excluded."scopes"
  returning * into v_row;
  return jsonb_build_object(
    'id', v_row."id",
    'tenant', v_row."tenant_id",
    'kind', v_row."kind",
    'name', v_row."name",
    'ref', v_row."credential_ref",
    'scopes', to_jsonb(v_row."scopes"),
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at"
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_workflow_definition (
  tenant      uuid,
  slug        text,
  name        text,
  description text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."workflow_definitions"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (tenant is not null and coalesce(better_supabase.can('tenant', tenant, 'workflow.edit'), false))) then
    raise exception 'You may not edit workflows here' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  insert into "better_supabase"."workflow_definitions" as x ("tenant_id", "slug", "name", "description", "created_by")
  values (tenant, slug, name, description, (select auth.uid()))
  on conflict on constraint workflow_definitions_tenant_slug_key do update set
    "name" = excluded."name",
    "description" = excluded."description",
    "updated_at" = now()
  returning * into v_row;
  return jsonb_build_object(
    'id', v_row."id",
    'tenant', v_row."tenant_id",
    'slug', v_row."slug",
    'name', v_row."name",
    'description', v_row."description",
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'updatedAt', v_row."updated_at"
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_workflow_draft (
  definition uuid,
  graph      jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_tenant uuid;
  v_row "better_supabase"."workflow_versions"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."workflow_definitions" x where x."id" = definition for update;
  if not found then
    raise exception 'No such workflow' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'workflow.edit'), false))) then
    raise exception 'You may not edit this workflow' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  if jsonb_typeof(graph) <> 'object' then
    raise exception 'A graph is an object' using errcode = '22023', hint = 'WORKFLOW_GRAPH_INVALID';
  end if;
  update "better_supabase"."workflow_versions" x set "graph" = graph, "compiled" = null
  where x."definition_id" = definition and x."status" = 'draft'
  returning * into v_row;
  if not found then
    insert into "better_supabase"."workflow_versions" ("definition_id", "version", "graph", "created_by")
    values (
      definition,
      coalesce((select max(y."version") from "better_supabase"."workflow_versions" y where y."definition_id" = definition), 0) + 1,
      graph,
      (select auth.uid())
    )
    returning * into v_row;
  end if;
  update "better_supabase"."workflow_definitions" x set "updated_at" = now() where x."id" = definition;
  return jsonb_build_object(
    'id', v_row."id",
    'definition', v_row."definition_id",
    'version', v_row."version",
    'status', v_row."status",
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'publishedAt', v_row."published_at",
    'graph', v_row."graph",
    'compiled', v_row."compiled"
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_workflow_trigger (
  definition uuid,
  kind       text,
  config     jsonb   DEFAULT '{}'::jsonb,
  enabled    boolean DEFAULT true,
  trigger    uuid    DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_tenant uuid;
  v_row "better_supabase"."workflow_triggers"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."workflow_definitions" x where x."id" = definition;
  if not found then
    raise exception 'No such workflow' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'workflow.edit'), false))) then
    raise exception 'You may not edit this workflow' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  if trigger is null then
    insert into "better_supabase"."workflow_triggers" ("definition_id", "kind", "config", "enabled")
    values (definition, kind, coalesce(config, '{}'::jsonb), coalesce(enabled, true))
    returning * into v_row;
  else
    update "better_supabase"."workflow_triggers" x set
      "kind" = kind,
      "config" = coalesce(config, '{}'::jsonb),
      "enabled" = coalesce(enabled, true),
      "updated_at" = now()
    where x."id" = trigger and x."definition_id" = definition
    returning * into v_row;
    if not found then
      raise exception 'No such trigger' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
    end if;
    if kind <> 'webhook' then
      delete from "better_supabase"."workflow_webhook_tokens" x where x."trigger_id" = trigger;
    end if;
  end if;
  return jsonb_build_object(
    'id', v_row."id",
    'definition', v_row."definition_id",
    'kind', v_row."kind",
    'config', v_row."config",
    'enabled', v_row."enabled",
    'createdAt', v_row."created_at",
    'updatedAt', v_row."updated_at"
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.send_message (
  conversation uuid,
  input        jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_conv "better_supabase"."conversations"%rowtype;
  v_msg "better_supabase"."inbox_messages"%rowtype;
  v_author_type text;
  v_direction text;
  v_kind text := coalesce(input ->> 'kind', 'message');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_conv from "better_supabase"."conversations" where "id" = send_message.conversation for update;
  if not found then
    raise exception 'conversation not found' using errcode = 'P0002', hint = 'CONVERSATION_NOT_FOUND';
  end if;
  if coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    v_author_type := coalesce(input ->> 'author_type', 'bot');
    v_direction := case when v_author_type = 'contact' then 'inbound' else 'outbound' end;
  elsif exists (select 1 from "better_supabase"."contacts" c where c."id" = v_conv."contact_id" and c."user_id" = (select auth.uid())) then
    -- The conversation's own contact writes as the contact, staff included.
    if v_kind <> 'message' then
      raise exception 'contacts cannot write notes' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
    end if;
    v_author_type := 'contact';
    v_direction := 'inbound';
  elsif coalesce(better_supabase.can('tenant', v_conv."tenant_id", 'inbox.reply'), false) then
    v_author_type := 'agent';
    v_direction := 'outbound';
  else
    raise exception 'not allowed to write in this conversation' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  v_msg := "better_supabase"."inbox_add_message"(v_conv."id", coalesce(input, '{}'::jsonb) - 'author_type', v_author_type, (select auth.uid()), v_direction);
  if v_author_type = 'agent' and v_kind = 'message' and v_conv."bot_mode" = 'bot' then
    update "better_supabase"."conversations" set "bot_mode" = 'human' where "id" = v_conv."id" returning * into v_conv;
    insert into "better_supabase"."conversation_events" ("tenant_id", "conversation_id", "type", "actor_id", "data")
  values (v_conv."tenant_id", v_conv."id", 'handoff', (select auth.uid()), jsonb_build_object('from', 'bot', 'to', 'human', 'reason', 'agent_reply'));
  end if;
  return to_jsonb(v_msg);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.send_notification (
  notification jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_type text := notification ->> 'type';
  v_tenant uuid := nullif(notification ->> 'tenant', '')::uuid;
  v_actor uuid := coalesce(nullif(notification ->> 'actor', '')::uuid, auth.uid());
  v_subject_type text := notification ->> 'subject_type';
  v_subject_id text := notification ->> 'subject_id';
  v_priority text := coalesce(notification ->> 'priority', 'normal');
  v_key text := nullif(notification ->> 'key', '');
  v_activity text := coalesce(notification ->> 'activity', 'participating');
  v_channels text[] := case
    when jsonb_typeof(notification -> 'channels') = 'array'
      then array(select jsonb_array_elements_text(notification -> 'channels'))
    else array['in_app']::text[]
  end;
  v_recipients uuid[] := array(
    select x::uuid from jsonb_array_elements_text(coalesce(notification -> 'recipients', '[]')) x
  );
  v_extra uuid[];
  v_event uuid;
  v_want_members uuid[];
  v_want_channels text[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_type is null or btrim(v_type) = '' then
    raise exception 'A notification needs a type' using errcode = '22023', hint = 'NOTIFICATION_TYPE_REQUIRED';
  end if;
  if not (v_priority = any(array['low', 'normal', 'high', 'urgent']::text[])) then
    raise exception 'Unknown notification priority' using errcode = '22023', hint = 'NOTIFICATION_PRIORITY_UNKNOWN';
  end if;
  if v_activity not in ('participating', 'all') then
    raise exception 'activity must be participating or all' using errcode = '22023', hint = 'NOTIFICATION_ACTIVITY_UNKNOWN';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    if v_tenant is null or not coalesce(better_supabase.member_can(auth.uid(), v_tenant, 'notifications.send'), false) then
      raise exception 'Not allowed to send notifications here' using errcode = '42501', hint = 'NOTIFICATION_FORBIDDEN';
    end if;
    v_actor := auth.uid();
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_notification_send"(jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::jsonb)', v_hook::oid::regproc)
        using notification;
    end if;
  end;
  if to_regprocedure('"public"."notification_audience"(jsonb)') is not null then
    execute format('select %s($1)', to_regprocedure('"public"."notification_audience"(jsonb)')::oid::regproc) into v_extra using notification;
    v_recipients := v_recipients || coalesce(v_extra, '{}');
  end if;
  if v_subject_type is not null and v_subject_id is not null then
    -- watchers: false sends to the named recipients only; ignore still holds.
    if coalesce((notification ->> 'watchers')::boolean, true) then
      v_recipients := v_recipients || array(
        select s."user_id" from "better_supabase"."notification_subscriptions" s
        where s."subject_type" = v_subject_type and s."subject_id" = v_subject_id and s."organization_id" is not distinct from v_tenant
          and (s."level" = 'all' or (v_activity = 'participating' and s."level" = 'participating'))
      );
    end if;
    v_recipients := array(
      select x from unnest(v_recipients) x
      where not exists (
        select 1 from "better_supabase"."notification_subscriptions" s
        where s."subject_type" = v_subject_type and s."subject_id" = v_subject_id and s."organization_id" is not distinct from v_tenant
          and s."level" = 'ignore' and s."user_id" = x
      )
    );
  end if;
  
  if nullif(notification ->> 'permission', '') is not null and v_tenant is null then
    raise exception 'A permission audience needs a tenant' using errcode = '22023', hint = 'NOTIFICATION_PERMISSION_NEEDS_TENANT';
  end if;
  if nullif(notification ->> 'permission', '') is not null then
    v_recipients := v_recipients || coalesce(array(
      select m."user_id"
      from "public"."memberships" m
      where m."organization_id" = v_tenant
        and coalesce(better_supabase.can_user(m."user_id", 'tenant', v_tenant, notification ->> 'permission'), false)
      
    ), '{}');
  end if;
  -- exclude: users the composer already reached (the mentioned ones, say).
  if jsonb_typeof(notification -> 'exclude') = 'array' then
    v_recipients := array(
      select x from unnest(v_recipients) x
      where not x = any (array(select e::uuid from jsonb_array_elements_text(notification -> 'exclude') e))
    );
  end if;
  if v_actor is not null and not coalesce((notification ->> 'include_actor')::boolean, false) then
    v_recipients := array_remove(v_recipients, v_actor);
  end if;
  if v_tenant is not null then
    v_recipients := array(
      select x from unnest(v_recipients) x
      where coalesce(better_supabase.member_can(x, v_tenant, 'notifications.read'), false)
    );
  end if;
  v_recipients := array(select distinct x from unnest(v_recipients) x where x is not null);
  if cardinality(v_recipients) > 1000 then
    raise exception 'A notification reaches at most 1000 recipients' using errcode = '22023', hint = 'NOTIFICATION_TOO_MANY_RECIPIENTS';
  end if;
  select coalesce(array_agg(w.member), '{}'), coalesce(array_agg(w.channel), '{}')
  into v_want_members, v_want_channels
  from (
    select w.member, w.channel from (
      select distinct on (x, c) x as member, c as channel, coalesce(p."enabled", case c when 'in_app' then true else false end) as enabled
      from unnest(v_recipients) x cross join unnest(v_channels) c
      left join "better_supabase"."notification_preferences" p
        on p."user_id" = x and p."channel" = c
        and (p."type" = v_type or p."type" = '*')
        and (p."organization_id" is null or p."organization_id" = v_tenant)
      order by x, c, p."organization_id" is null, p."type" = '*'
    ) w
    where w.enabled
  ) w;
  v_recipients := array(select distinct x from unnest(v_want_members) x);
  if cardinality(v_recipients) = 0 then
    return null;
  end if;

  if v_key is not null then
    select ev."id" into v_event from "better_supabase"."notification_events" ev
    where ev."idempotency_key" = v_key and ev."organization_id" is not distinct from v_tenant;
  end if;
  if v_event is null then
    insert into "better_supabase"."notification_events" ("type", "data", "organization_id", "actor_id", "subject_type", "subject_id", "subject_label", "summary", "action_path", "priority", "idempotency_key", "created_by")
    values (v_type, coalesce(notification -> 'data', '{}'), v_tenant, v_actor, v_subject_type, v_subject_id, notification ->> 'subject_label', notification ->> 'summary', notification ->> 'action_path', v_priority, v_key, auth.uid())
    on conflict do nothing
    returning "id" into v_event;
  end if;
  if v_event is null then
    select ev."id" into v_event from "better_supabase"."notification_events" ev
    where ev."idempotency_key" = v_key and ev."organization_id" is not distinct from v_tenant;
  end if;

  insert into "better_supabase"."notification_recipients" ("event_id", "organization_id", "user_id", "dismissed_at", "resolved_at", "created_at")
  select v_event, v_tenant, x, case when exists (select 1 from unnest(v_want_members, v_want_channels) w(member, channel) where w.member = x and w.channel = 'in_app') then null else now() end, case when coalesce((notification ->> 'resolved')::boolean, false) then now() end, clock_timestamp()
  from unnest(v_recipients) x
  on conflict do nothing;
  insert into "better_supabase"."notification_deliveries" ("recipient_id", "organization_id", "channel", "status", "delivered_at")
  select rc."id", v_tenant, c, case when c = 'in_app' then 'sent' else 'pending' end, case when c = 'in_app' then now() end
  from "better_supabase"."notification_recipients" rc
  join unnest(v_want_members, v_want_channels) w(member, c) on w.member = rc."user_id"
  where rc."event_id" = v_event
  on conflict do nothing;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_notify"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_event;
    end if;
  end;
  null;
  return jsonb_build_object('id', v_event, 'recipients', to_jsonb(v_recipients));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_agent_skills (
  agent_id uuid,
  skills   jsonb
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."agents"%rowtype;
  v_items jsonb := case when jsonb_typeof(set_agent_skills.skills) = 'object' then set_agent_skills.skills -> 'items' else set_agent_skills.skills end;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."agents" x where x."id" = set_agent_skills.agent_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai.moderate'), false)) then
    raise exception 'agent % not found', set_agent_skills.agent_id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  if jsonb_typeof(v_items) is distinct from 'array' then
    raise exception 'skills must be a list' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  delete from "better_supabase"."agent_skills" k where k."agent_id" = v_row."id";
  insert into "better_supabase"."agent_skills" ("agent_id", "provider", "reference")
  select v_row."id", e ->> 'provider', e -> 'reference' from jsonb_array_elements(v_items) e;
  get diagnostics v_count = row_count;
  return v_count;
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', set_ai_tool_policy.tenant, 'ai_chat.admin'), false)) then
    raise exception 'You may not change tool policies here' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  if set_ai_tool_policy.policy is null then
    delete from "better_supabase"."ai_tool_policies" x where x."organization_id" = set_ai_tool_policy.tenant and x."tool" = set_ai_tool_policy.tool;
    perform better_supabase.audit_event(
    event_type => 'ai_tool_policy.set',
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
  perform better_supabase.audit_event(
    event_type => 'ai_tool_policy.set',
    category => 'ai',
    target_type => 'ai_tool_policy',
    record_id => set_ai_tool_policy.tool,
    tenant => (set_ai_tool_policy.tenant)::uuid,
    metadata => jsonb_build_object('organizationId', set_ai_tool_policy.tenant::text, 'tool', set_ai_tool_policy.tool, 'policy', set_ai_tool_policy.policy)
  );
  return jsonb_build_object('tool', set_ai_tool_policy.tool, 'policy', set_ai_tool_policy.policy);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_bot_mode (
  conversation uuid,
  mode         text,
  reason       text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_conv "better_supabase"."conversations"%rowtype;
  v_before text;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_conv from "better_supabase"."conversations" where "id" = set_bot_mode.conversation for update;
  if not found then
    raise exception 'conversation not found' using errcode = 'P0002', hint = 'CONVERSATION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_conv."tenant_id", 'inbox.reply'), false)) then
    raise exception 'not allowed to change this conversation' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  v_before := v_conv."bot_mode";
  update "better_supabase"."conversations" set "bot_mode" = mode where "id" = v_conv."id" returning * into v_conv;
  if v_before is distinct from mode then
    insert into "better_supabase"."conversation_events" ("tenant_id", "conversation_id", "type", "actor_id", "data")
  values (v_conv."tenant_id", v_conv."id", 'handoff', (select auth.uid()), jsonb_build_object('from', v_before, 'to', set_bot_mode.mode, 'reason', set_bot_mode.reason));
    if v_before = 'bot' and mode = 'human' then
  v_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
  perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'inbox.handoff',
        'tenant', v_conv."tenant_id",
        'actor', (select auth.uid()),
        'subject_type', 'conversation',
        'subject_id', v_conv."id"::text,
        'summary', coalesce(set_bot_mode.reason, v_conv."last_message_preview"),
        'recipients', case when v_conv."assignee_id" is not null then to_jsonb(array[v_conv."assignee_id"])
    else coalesce((select jsonb_agg(m."user_id") from "better_supabase"."inbox_members" m where m."inbox_id" = v_conv."inbox_id"), '[]'::jsonb) end,
        'key', 'inbox.handoff:' || v_conv."id"::text || ':' || extract(epoch from now())::text,
        'data', jsonb_build_object('conversationId', v_conv."id", 'reason', set_bot_mode.reason)
      ));
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
      null;
    end if;
  end if;
  return "better_supabase"."inbox_conversation_json"(v_conv."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_conversation_status (
  conversation  uuid,
  status        text,
  snoozed_until timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_conv "better_supabase"."conversations"%rowtype;
  v_before text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_conv from "better_supabase"."conversations" where "id" = set_conversation_status.conversation for update;
  if not found then
    raise exception 'conversation not found' using errcode = 'P0002', hint = 'CONVERSATION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_conv."tenant_id", 'inbox.reply'), false)) then
    raise exception 'not allowed to change this conversation' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  if status = 'snoozed' and snoozed_until is null then
    raise exception 'snoozing needs snoozed_until' using errcode = '22023', hint = 'INBOX_SNOOZE_UNTIL';
  end if;
  v_before := v_conv."status";
  update "better_supabase"."conversations" set
    "status" = set_conversation_status.status,
    "snoozed_until" = case when set_conversation_status.status = 'snoozed' then set_conversation_status.snoozed_until end,
    "resolved_at" = case when set_conversation_status.status = 'resolved' then now() end
  where "id" = v_conv."id"
  returning * into v_conv;
  if v_before is distinct from status then
    insert into "better_supabase"."conversation_events" ("tenant_id", "conversation_id", "type", "actor_id", "data")
  values (v_conv."tenant_id", v_conv."id", 'status', (select auth.uid()), jsonb_build_object('from', v_before, 'to', set_conversation_status.status));
    if status = 'resolved' then
      null;
    elsif v_before = 'resolved' then
      null;
    end if;
  end if;
  return "better_supabase"."inbox_conversation_json"(v_conv."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_flag_override (
  key     text,
  variant text,
  tenant  uuid DEFAULT NULL::uuid,
  member  uuid DEFAULT NULL::uuid
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.is_platform('flags.manage'), false)) then
    raise exception 'Not allowed to manage feature flags' using errcode = '42501', hint = 'FLAGS_FORBIDDEN';
  end if;
  if (tenant is null) = (member is null) then
    raise exception 'Pass a tenant or a member, not both' using errcode = '22023', hint = 'FLAGS_OVERRIDE_TARGET';
  end if;
  if variant is null then
    delete from "better_supabase"."flag_overrides" v
    where v."flag_key" = set_flag_override.key
      and v."organization_id" is not distinct from set_flag_override.tenant
      and v."user_id" is not distinct from set_flag_override.member;
    if not found then
      return false;
    end if;
    perform better_supabase.audit_event(
    event_type => 'flag.override_set',
    category => 'configuration',
    target_type => 'flag',
    record_id => set_flag_override.key,
    tenant => (set_flag_override.tenant)::uuid,
    metadata => jsonb_build_object('key', set_flag_override.key, 'variant', set_flag_override.variant, 'organizationId', set_flag_override.tenant::text, 'userId', set_flag_override.member)
  );
    return true;
  end if;
  insert into "better_supabase"."flag_overrides" ("flag_key", "organization_id", "user_id", "variant")
  values (set_flag_override.key, set_flag_override.tenant, set_flag_override.member, set_flag_override.variant)
  on conflict ("flag_key", "organization_id", "user_id") do update set "variant" = excluded."variant";
  perform better_supabase.audit_event(
    event_type => 'flag.override_set',
    category => 'configuration',
    target_type => 'flag',
    record_id => set_flag_override.key,
    tenant => (set_flag_override.tenant)::uuid,
    metadata => jsonb_build_object('key', set_flag_override.key, 'variant', set_flag_override.variant, 'organizationId', set_flag_override.tenant::text, 'userId', set_flag_override.member)
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_inbox_member (
  inbox  uuid,
  member uuid,
  role   text DEFAULT 'agent'::text
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
  select "tenant_id" into v_tenant from "better_supabase"."inboxes" where "id" = set_inbox_member.inbox;
  if not found then
    raise exception 'inbox not found' using errcode = 'P0002', hint = 'INBOX_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'inbox.manage'), false)) then
    raise exception 'not allowed to manage inboxes' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  if role is null then
    delete from "better_supabase"."inbox_members" m where m."inbox_id" = set_inbox_member.inbox and m."user_id" = member;
    return found;
  end if;
  if not coalesce(better_supabase.can_user(member, 'tenant', v_tenant, 'inbox.read'), false) then
    raise exception 'user cannot read this inbox' using errcode = '22023', hint = 'INBOX_MEMBER_INVALID';
  end if;
  insert into "better_supabase"."inbox_members" ("inbox_id", "user_id", "role") values (set_inbox_member.inbox, member, role)
  on conflict ("inbox_id", "user_id") do update set "role" = excluded."role";
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_inbox_team_member (
  team    uuid,
  member  uuid,
  present boolean DEFAULT true
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not coalesce(present, true) then
    return "better_supabase"."remove_team_member"(set_inbox_team_member.team, member);
  end if;
  return "better_supabase"."add_team_member"(set_inbox_team_member.team, member);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_notification_preference (
  type    text,
  channel text,
  enabled boolean,
  tenant  uuid    DEFAULT NULL::uuid
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null then
    raise exception 'Sign in to change notification preferences' using errcode = '42501', hint = 'NOTIFICATION_FORBIDDEN';
  end if;
  if set_notification_preference.tenant is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))
    and not coalesce(better_supabase.member_can(auth.uid(), set_notification_preference.tenant, 'notifications.read'), false) then
    raise exception 'Not a member of this organization' using errcode = '42501', hint = 'NOTIFICATION_FORBIDDEN';
  end if;
  delete from "better_supabase"."notification_preferences" p
  where p."user_id" = auth.uid()
    and p."type" = set_notification_preference.type
    and p."channel" = set_notification_preference.channel
    and p."organization_id" is not distinct from set_notification_preference.tenant;
  if set_notification_preference.enabled is not null then
    insert into "better_supabase"."notification_preferences" ("user_id", "organization_id", "type", "channel", "enabled")
    values (auth.uid(), set_notification_preference.tenant, set_notification_preference.type, set_notification_preference.channel, set_notification_preference.enabled);
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_notification_subscription (
  subject_type text,
  subject_id   text,
  level        text,
  tenant       uuid    DEFAULT NULL::uuid,
  member       uuid    DEFAULT NULL::uuid,
  if_absent    boolean DEFAULT false
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_user uuid := coalesce(set_notification_subscription.member, auth.uid());
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_user is distinct from auth.uid() and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not (
    coalesce(set_notification_subscription.if_absent, false) and set_notification_subscription.level is not null and set_notification_subscription.tenant is not null
    and coalesce(better_supabase.member_can(auth.uid(), set_notification_subscription.tenant, 'notifications.send'), false)
    and coalesce(better_supabase.member_can(v_user, set_notification_subscription.tenant, 'notifications.read'), false)
  ) then
    raise exception 'Only the service, or a sender with if_absent, sets subscriptions for others' using errcode = '42501', hint = 'NOTIFICATION_FORBIDDEN';
  end if;
  if set_notification_subscription.level is not null and set_notification_subscription.level not in ('participating', 'all', 'ignore') then
    raise exception 'level must be participating, all or ignore' using errcode = '22023', hint = 'NOTIFICATION_LEVEL_UNKNOWN';
  end if;
  if set_notification_subscription.tenant is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))
    and not coalesce(better_supabase.member_can(auth.uid(), set_notification_subscription.tenant, 'notifications.read'), false) then
    raise exception 'Not a member of this organization' using errcode = '42501', hint = 'NOTIFICATION_FORBIDDEN';
  end if;
  if coalesce(set_notification_subscription.if_absent, false) then
    if set_notification_subscription.level is not null and not exists (
      select 1 from "better_supabase"."notification_subscriptions" s
      where s."user_id" = v_user
        and s."subject_type" = set_notification_subscription.subject_type
        and s."subject_id" = set_notification_subscription.subject_id
        and s."organization_id" is not distinct from set_notification_subscription.tenant
    ) then
      insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
      values (set_notification_subscription.tenant, v_user, set_notification_subscription.subject_type, set_notification_subscription.subject_id, set_notification_subscription.level);
    end if;
    return;
  end if;
  delete from "better_supabase"."notification_subscriptions" s
  where s."user_id" = v_user
    and s."subject_type" = set_notification_subscription.subject_type
    and s."subject_id" = set_notification_subscription.subject_id
    and s."organization_id" is not distinct from set_notification_subscription.tenant;
  if set_notification_subscription.level is not null then
    insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
    values (set_notification_subscription.tenant, v_user, set_notification_subscription.subject_type, set_notification_subscription.subject_id, set_notification_subscription.level);
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.share_ai_chat (
  chat uuid,
  leaf text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_chat "better_supabase"."ai_chats";
  v_leaf text;
  v_token text := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  v_id uuid;
  v_created timestamptz;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_chat from "better_supabase"."ai_chats" x where x."id" = share_ai_chat.chat;
  if not found or v_chat."owner_id" is distinct from auth.uid() then
    raise exception 'No chat %', share_ai_chat.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  if not coalesce(better_supabase.can('tenant', v_chat."organization_id", 'ai_chat.share'), false) then
    raise exception 'You may not share chats here' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  v_leaf := coalesce(share_ai_chat.leaf, v_chat."current_leaf_id");
  if v_leaf is null or not exists (select 1 from "better_supabase"."ai_messages" x where x."chat_id" = v_chat."id" and x."id" = v_leaf) then
    raise exception 'Nothing to share yet' using errcode = 'P0002', hint = 'AI_MESSAGE_NOT_FOUND';
  end if;
  insert into "better_supabase"."ai_chat_shares" ("chat_id", "token_hash", "leaf_id", "created_by")
  values (v_chat."id", encode(sha256(convert_to(v_token, 'UTF8')), 'hex'), v_leaf, auth.uid())
  returning "id", "created_at" into v_id, v_created;
  perform better_supabase.audit_event(
    event_type => 'ai_chat.shared',
    category => 'ai',
    target_type => 'ai_chat_share',
    record_id => v_id::text,
    tenant => (v_chat."organization_id")::uuid,
    metadata => jsonb_build_object('chatId', v_chat."id", 'shareId', v_id, 'organizationId', v_chat."organization_id"::text, 'ownerId', v_chat."owner_id", 'leafId', v_leaf),
    idempotency_key => 'ai_chat.shared:' || v_id::text
  );
  return jsonb_build_object('id', v_id, 'token', v_token, 'leaf_id', v_leaf, 'created_at', v_created);
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
  v_contact "better_supabase"."contacts"%rowtype;
  v_conv "better_supabase"."conversations"%rowtype;
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
  v_contact := "better_supabase"."inbox_resolve_contact"(v_inbox."tenant_id", v_contact_input);
  insert into "better_supabase"."conversations" ("tenant_id", "inbox_id", "contact_id", "subject", "priority", "bot_mode", "thread_id", "assignee_id", "metadata")
  values (
    v_inbox."tenant_id", v_inbox."id", v_contact."id", input ->> 'subject', coalesce(input ->> 'priority', 'normal'),
    coalesce(input ->> 'bot_mode', v_inbox."bot_mode"), input ->> 'thread_id',
    case when v_staff then (input ->> 'assignee_id')::uuid end, coalesce(input -> 'metadata', '{}'::jsonb)
  )
  returning * into v_conv;
  if v_conv."thread_id" is null then
    update "better_supabase"."conversations" set "thread_id" = 'inbox:' || "id"::text
    where "id" = v_conv."id"
    returning * into v_conv;
  end if;
  insert into "better_supabase"."conversation_events" ("tenant_id", "conversation_id", "type", "actor_id", "data")
  values (v_conv."tenant_id", v_conv."id", 'opened', (select auth.uid()), '{}'::jsonb);
  null;
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

CREATE OR REPLACE FUNCTION better_supabase.stream_cancel (
  stream_id text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_wake boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "better_supabase"."streams" set "cancel_requested_at" = now()
  where "id" = stream_cancel.stream_id
    and "cancel_requested_at" is null
    and "closed_at" is null
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "owner_id" = (select auth.uid()))
  returning "wake" into v_wake;
  if not found then
    return false;
  end if;
  
  if v_wake and to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send('{}'::jsonb, 'cancel', 'stream:' || stream_cancel.stream_id, true);
  end if;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.suggest_ai_document_edit (
  document_id    uuid,
  original_text  text,
  suggested_text text,
  description    text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_doc "better_supabase"."ai_documents"%rowtype;
  v_row "better_supabase"."ai_suggestions"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_doc from "better_supabase"."ai_documents" x where x."id" = suggest_ai_document_edit.document_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_doc."owner_id" = (select auth.uid()) or coalesce(better_supabase.can('tenant', v_doc."organization_id", 'ai.admin'), false) or (v_doc."chat_id" is not null and "better_supabase"."ai_chat_can_read"(v_doc."chat_id")))) then
    raise exception 'document % not found', document_id using errcode = 'P0002', hint = 'AI_DOCUMENT_NOT_FOUND';
  end if;
  insert into "better_supabase"."ai_suggestions" ("document_id", "version", "original_text", "suggested_text", "description", "created_by")
  values (v_doc."id", v_doc."current_version", suggest_ai_document_edit.original_text, suggest_ai_document_edit.suggested_text, suggest_ai_document_edit.description, auth.uid())
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'document_id', v_row."document_id", 'version', v_row."version", 'original_text', v_row."original_text", 'suggested_text', v_row."suggested_text", 'description', v_row."description", 'created_by', v_row."created_by", 'created_at', v_row."created_at", 'resolved_at', v_row."resolved_at", 'accepted', v_row."accepted");
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
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_chat."owner_id" = (select auth.uid())) then
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

CREATE OR REPLACE FUNCTION better_supabase.switch_organization (
  organization uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  me uuid := auth.uid();
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if me is null or not exists (select 1 from "public"."memberships" m where m."organization_id" = organization and m."user_id" = me) then
    raise exception 'Not a member' using errcode = 'P0002', hint = 'ORGANIZATION_NOT_MEMBER';
  end if;
  if not (exists (select 1 from "public"."organizations" o where o."id" = organization) and not better_supabase.tenant_disabled(organization)) then
    raise exception 'The organization is unavailable' using errcode = '42501', hint = 'ORGANIZATION_DISABLED';
  end if;
  update auth.users
  set raw_app_meta_data = coalesce(raw_app_meta_data, '{}') || jsonb_build_object('tenant_id', organization::text)
  where id = me;
  update "public"."memberships" set "last_used_at" = now() where "organization_id" = organization and "user_id" = me;
  null;
  return jsonb_build_object('organization_id', organization, 'refresh', true);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.team_ids_of (
  member uuid
)
  RETURNS SETOF uuid
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select "team_id" from "better_supabase"."team_members" where "user_id" = team_ids_of.member
$function$;

CREATE OR REPLACE FUNCTION better_supabase.transfer_ownership (
  organization uuid,
  new_owner    uuid,
  former_role  text DEFAULT 'admin'::text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  me uuid := auth.uid();
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), organization, 'organization.transfer_ownership'), false)) then
    raise exception 'Not allowed to transfer ownership' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  -- Only an owner hands ownership on, so the permission alone can't make its
  -- holder an owner.
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not exists (
    select 1 from "public"."memberships" m where m."organization_id" = organization and m."user_id" = me and m."role" = 'owner'
  ) then
    raise exception 'Only an owner can transfer ownership' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  if not (exists (select 1 from "public"."organizations" o where o."id" = organization) and not better_supabase.tenant_disabled(organization)) then
    raise exception 'The organization is unavailable' using errcode = '42501', hint = 'ORGANIZATION_DISABLED';
  end if;
  if not (former_role = any (array['owner', 'admin', 'member']::text[])) then
    raise exception 'Unknown role %', former_role using errcode = '22023', hint = 'ORGANIZATION_ROLE_UNKNOWN';
  end if;
  if not exists (select 1 from "public"."memberships" m where m."organization_id" = organization and m."user_id" = new_owner) then
    raise exception 'The new owner must be a member' using errcode = 'P0002', hint = 'ORGANIZATION_NOT_MEMBER';
  end if;
  if better_supabase.user_disabled(new_owner) then
    raise exception 'The new owner is disabled' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  -- One statement for both rows, so a statement-level guard on the number of
  -- owners sees the transfer as a whole.
  update "public"."memberships" m set "role" = case
      when m."user_id" = new_owner then 'owner'
      else former_role
    end
  where m."organization_id" = organization
    and (m."user_id" = new_owner
      or (me is not null and me <> new_owner and m."user_id" = me and m."role" = 'owner'));
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_member_change"(uuid, uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text)', v_hook::oid::regproc)
        using organization, new_owner, 'owner';
    end if;
  end;
  perform better_supabase.audit_event(
    event_type => 'organization.ownership_transferred',
    category => 'membership',
    target_type => 'user',
    record_id => new_owner::text,
    tenant => (organization)::uuid,
    metadata => jsonb_build_object('organizationId', organization::text, 'userId', new_owner, 'role', 'owner')
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.unregister_push_device (
  token text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_user uuid := auth.uid();
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_user is null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Sign in first' using errcode = '42501', hint = 'PUSH_FORBIDDEN';
  end if;
  delete from "better_supabase"."push_devices" x
  where x."token" = unregister_push_device.token
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or x."user_id" = v_user)
  returning x."id", x."user_id" into v_id, v_user;
  if v_id is null then
    return false;
  end if;
  perform better_supabase.audit_event(
    event_type => 'push.device_unregistered',
    category => 'security',
    target_type => 'push_device',
    record_id => v_id::text,
    metadata => jsonb_build_object('deviceId', v_id::text, 'userId', v_user::text)
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_ai_chat (
  chat   uuid,
  fields jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_fields jsonb := coalesce(update_ai_chat.fields, '{}'::jsonb);
  v_row "better_supabase"."ai_chats";
  v_project uuid := (v_fields ->> 'project_id')::uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."ai_chats" x where x."id" = update_ai_chat.chat for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = (select auth.uid())) then
    raise exception 'No chat %', update_ai_chat.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  if v_project is not null and not exists (select 1 from "better_supabase"."ai_projects" pr where pr."id" = v_project and pr."owner_id" = v_row."owner_id" and pr."organization_id" = v_row."organization_id") then
    raise exception 'No project %', v_project using errcode = 'P0002', hint = 'AI_PROJECT_NOT_FOUND';
  end if;
  if v_fields ->> 'visibility' = 'organization' and v_row."visibility" <> 'organization'
    and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai_chat.share'), false)) then
    raise exception 'You may not share chats here' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  update "better_supabase"."ai_chats" x set
    "title" = case when v_fields ? 'title' then coalesce(v_fields ->> 'title', '') else x."title" end,
    "model" = case when v_fields ? 'model' then v_fields ->> 'model' else x."model" end,
    "project_id" = case when v_fields ? 'project_id' then v_project else x."project_id" end,
    "agent_id" = case when v_fields ? 'agent_id' then v_fields ->> 'agent_id' else x."agent_id" end,
    "visibility" = case when v_fields ? 'visibility' then coalesce(v_fields ->> 'visibility', 'private') else x."visibility" end,
    "pinned" = case when v_fields ? 'pinned' then coalesce((v_fields ->> 'pinned')::boolean, false) else x."pinned" end,
    "archived_at" = case
      when not v_fields ? 'archived' then x."archived_at"
      when coalesce((v_fields ->> 'archived')::boolean, false) then coalesce(x."archived_at", now())
    end,
    "is_temporary" = x."is_temporary" and coalesce((v_fields ->> 'is_temporary')::boolean, true),
    "expires_at" = case when x."is_temporary" and coalesce((v_fields ->> 'is_temporary')::boolean, true) then x."expires_at" end,
    "updated_at" = now()
  where x."id" = update_ai_chat.chat
  returning * into v_row;
  perform "better_supabase"."ai_chat_notify"(v_row."id", v_row."owner_id", 'chat.updated', '{}'::jsonb, not v_row."is_temporary");
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'project_id', v_row."project_id", 'agent_id', v_row."agent_id", 'title', v_row."title", 'model', v_row."model", 'visibility', v_row."visibility", 'pinned', v_row."pinned", 'archived_at', v_row."archived_at", 'is_temporary', v_row."is_temporary", 'expires_at', v_row."expires_at", 'current_leaf_id', v_row."current_leaf_id", 'active_stream_id', v_row."active_stream_id", 'active_run_id', v_row."active_run_id", 'last_message_at', v_row."last_message_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_ai_document (
  document_id      uuid,
  content          text    DEFAULT NULL::text,
  title            text    DEFAULT NULL::text,
  message_id       text    DEFAULT NULL::text,
  expected_version integer DEFAULT NULL::integer,
  storage_path     text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."ai_documents"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."ai_documents" x where x."id" = update_ai_document.document_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai.admin'), false)) then
    raise exception 'document % not found', document_id using errcode = 'P0002', hint = 'AI_DOCUMENT_NOT_FOUND';
  end if;
  if expected_version is not null and expected_version <> v_row."current_version" then
    raise exception 'document % is at version %', document_id, v_row."current_version" using errcode = '40001', hint = 'AI_DOCUMENT_CONFLICT';
  end if;
  insert into "better_supabase"."ai_document_versions" ("document_id", "version", "content", "storage_path", "created_by_message_id", "created_by")
  values (v_row."id", v_row."current_version" + 1, update_ai_document.content, update_ai_document.storage_path, update_ai_document.message_id, auth.uid());
  update "better_supabase"."ai_documents" x set
    "current_version" = v_row."current_version" + 1,
    "title" = coalesce(update_ai_document.title, x."title"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'chat_id', v_row."chat_id", 'kind', v_row."kind", 'title', v_row."title", 'current_version', v_row."current_version", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_inbox (
  inbox uuid,
  patch jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."inboxes"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."inboxes" where "id" = update_inbox.inbox for update;
  if not found then
    raise exception 'inbox not found' using errcode = 'P0002', hint = 'INBOX_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inbox.manage'), false)) then
    raise exception 'not allowed to manage inboxes' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  update "better_supabase"."inboxes" set
    "name" = coalesce(patch ->> 'name', "name"),
    "settings" = "settings" || coalesce(patch -> 'settings', '{}'::jsonb),
    "bot_mode" = coalesce(patch ->> 'bot_mode', "bot_mode"),
    "channel_address" = case when patch ? 'address' then patch ->> 'address' else "channel_address" end,
    "installation_id" = case when patch ? 'installation_id' then (patch ->> 'installation_id')::uuid else "installation_id" end,
    "archived_at" = case when patch ? 'archived' then (case when (patch ->> 'archived')::boolean then coalesce("archived_at", now()) end) else "archived_at" end
  where "id" = update_inbox.inbox
  returning * into v_row;
  return to_jsonb(v_row);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_invitation (
  invitation_id uuid,
  invitee_email text  DEFAULT NULL::text,
  invitee_role  text  DEFAULT NULL::text,
  prefill       jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
  current_invite "better_supabase"."invitations";
  updated "better_supabase"."invitations";
  tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if invitee_email is not null and btrim(invitee_email) = '' then
    raise exception 'The email address is empty' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  select * into current_invite from "better_supabase"."invitations" i
  where i."id" = invitation_id and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
  for update;
  if current_invite."id" is null then
    raise exception 'No open invitation %', invitation_id using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if current_invite."expires_at" < now() then
    raise exception 'The invitation has expired; resend it to renew it' using errcode = 'P0002', hint = 'INVITATION_EXPIRED';
  end if;
  tenant := current_invite."organization_id";
  if not service and not coalesce(better_supabase.member_can(auth.uid(), tenant, 'members.invite'), false) then
    raise exception 'Not allowed to invite members' using errcode = '42501', hint = 'INVITATION_FORBIDDEN';
  end if;
  if better_supabase.tenant_disabled(tenant) or not exists (select 1 from "public"."organizations" o where o."id" = tenant) then
    raise exception 'The organization is not active' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if invitee_role is not null and not (invitee_role = any (array['owner', 'admin', 'member']::text[])) then
    raise exception 'Unknown role %', invitee_role using errcode = '23514', hint = 'INVITATION_ROLE_UNKNOWN';
  end if;
  if not service and (
    not better_supabase.can_assign(tenant, current_invite."role"::text)
    or (invitee_role is not null and not better_supabase.can_assign(tenant, (invitee_role)::text))
  ) then
    raise exception 'That role is above your own' using errcode = '42501', hint = 'INVITATION_ROLE_FORBIDDEN';
  end if;
  if invitee_email is not null and exists (
    select 1 from "public"."memberships" m join auth.users u on u.id = m."user_id"
    where m."organization_id" = tenant and lower(u.email) = lower(btrim(invitee_email))
  ) then
    raise exception '% is already a member', invitee_email using errcode = '23505', hint = 'INVITATION_ALREADY_MEMBER';
  end if;
  if invitee_email is not null then
    delete from "better_supabase"."invitations" i
    where i."organization_id" = tenant
      and lower(i."email") = lower(btrim(invitee_email))
      and i."id" <> invitation_id
      and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null;
  end if;
  updated := current_invite;
    if invitee_email is not null then
      updated."email" := lower(btrim(invitee_email));
    end if;
    if invitee_role is not null then
      updated."role" := invitee_role;
    end if;
    update "better_supabase"."invitations" i
    set "email" = updated."email",
      "role" = updated."role"
    where i."id" = invitation_id
    returning * into updated;
  perform better_supabase.audit_event(
    event_type => 'invitation.updated',
    category => 'membership',
    target_type => 'invitation',
    record_id => updated."id"::text,
    tenant => (tenant)::uuid,
    metadata => jsonb_build_object('invitationId', updated."id", 'organizationId', tenant::text, 'email', updated."email", 'role', updated."role")
  );
  return (jsonb_build_object(
    'id', updated."id",
    'tenant', updated."organization_id",
    'email', updated."email",
    'role', updated."role",
    'expires_at', updated."expires_at",
    'created_at', updated."created_at",
    'invited_by', updated."invited_by",
    'organization', (select jsonb_build_object('id', o."id", 'name', o."name")
      from "public"."organizations" o where o."id" = updated."organization_id"),
    'prefill', '{}'::jsonb,
    'inviter', (select jsonb_build_object('id', pr."id", 'username', pr."username", 'fullName', pr."full_name", 'firstName', pr."first_name", 'lastName', pr."last_name", 'avatar', pr."avatar_url")
      from "better_supabase"."profiles" pr where pr."id" = updated."invited_by"),
    'token', null
  ) || "better_supabase"."invitation_extra"(updated."id")) - 'token';
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_member_role (
  organization uuid,
  member       uuid,
  role         text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  previous text;
  previous_assignable text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), organization, 'members.update_role'), false)) then
    raise exception 'Not allowed to change roles' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  if not (exists (select 1 from "public"."organizations" o where o."id" = organization) and not better_supabase.tenant_disabled(organization)) then
    raise exception 'The organization is unavailable' using errcode = '42501', hint = 'ORGANIZATION_DISABLED';
  end if;
  if not (role = any (array['owner', 'admin', 'member']::text[])) then
    raise exception 'Unknown role %', role using errcode = '22023', hint = 'ORGANIZATION_ROLE_UNKNOWN';
  end if;
  select m."role", m."role"::text into previous, previous_assignable
  from "public"."memberships" m where m."organization_id" = organization and m."user_id" = member;
  if not found then
    raise exception 'Not a member' using errcode = 'P0002', hint = 'ORGANIZATION_NOT_MEMBER';
  end if;
  -- Checked here whatever sql.modules.organizations.options.assignmentGuard
  -- says: a guard that checks only client writes never sees this function's.
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and member = auth.uid() then
    raise exception 'You cannot change your own role' using errcode = '42501', hint = 'ORGANIZATION_SELF_ROLE';
  end if;
  if not better_supabase.can_assign(organization, previous_assignable)
    or not better_supabase.can_assign(organization, (role)::text) then
    raise exception 'That role is above your own' using errcode = '42501', hint = 'ORGANIZATION_ROLE_CEILING';
  end if;
  update "public"."memberships" set "role" = role
  where "organization_id" = organization and "user_id" = member;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_member_change"(uuid, uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text)', v_hook::oid::regproc)
        using organization, member, 'role';
    end if;
  end;
  perform better_supabase.audit_event(
    event_type => 'organization.role_changed',
    category => 'membership',
    target_type => 'user',
    record_id => member::text,
    tenant => (organization)::uuid,
    metadata => jsonb_build_object('organizationId', organization::text, 'userId', member, 'role', role, 'previousRole', previous)
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_organization (
  organization uuid,
  attrs        jsonb
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not coalesce(better_supabase.member_can(auth.uid(), organization, 'organization.update'), false) then
    raise exception 'Not allowed to update the organization' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  if attrs ? 'slug' then
    case "better_supabase"."organization_slug_problem"(attrs ->> 'slug', organization)
      when 'invalid' then raise exception 'Invalid slug "%"', attrs ->> 'slug' using errcode = '23514', hint = 'ORGANIZATION_SLUG_INVALID';
      when 'reserved' then raise exception 'The slug "%" is reserved', attrs ->> 'slug' using errcode = '23514', hint = 'ORGANIZATION_SLUG_RESERVED';
      when 'taken' then raise exception 'The slug "%" is taken', attrs ->> 'slug' using errcode = '23505', hint = 'ORGANIZATION_SLUG_TAKEN';
      else null;
    end case;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_organization_update"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using organization, attrs;
    end if;
  end;
  update "public"."organizations" o
  set "name" = case when attrs ? 'name' then r."name" else o."name" end,
    "slug" = case when attrs ? 'slug' then r."slug" else o."slug" end
  from jsonb_populate_record(null::"public"."organizations", attrs) r
  where o."id" = organization;
  if not found then
    raise exception 'No organization %', organization using errcode = 'P0002', hint = 'ORGANIZATION_NOT_FOUND';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_organization_update"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using organization, attrs;
    end if;
  end;
  perform better_supabase.audit_event(
    event_type => 'organization.updated',
    category => 'configuration',
    target_type => 'organization',
    record_id => organization::text,
    tenant => (organization)::uuid,
    metadata => jsonb_build_object('organizationId', organization::text, 'userId', auth.uid())
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_team (
  team        uuid,
  name        text,
  description text
)
  RETURNS jsonb
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
  select "tenant_id" into v_tenant from "better_supabase"."teams" where "id" = update_team.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  update "better_supabase"."teams"
  set "name" = coalesce(update_team.name, "name"),
      "description" = coalesce(update_team.description, "description"),
      "updated_at" = now()
  where "id" = update_team.team;
  perform better_supabase.audit_event(
    event_type => 'team.updated',
    category => 'membership',
    target_type => 'team',
    record_id => (update_team.team)::text,
    tenant => (v_tenant)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'id', update_team.team, 'name', update_team.name)
  );
  return jsonb_build_object('id', update_team.team);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.upsert_message_template (
  tenant uuid,
  input  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."message_templates"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', tenant, 'inbox.manage'), false)) then
    raise exception 'not allowed to manage templates' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  insert into "better_supabase"."message_templates" as t ("tenant_id", "inbox_id", "name", "channel", "language", "body", "variables", "external_id")
  values (tenant, (input ->> 'inbox_id')::uuid, input ->> 'name', input ->> 'channel', coalesce(input ->> 'language', 'en'), input ->> 'body', coalesce(input -> 'variables', '[]'::jsonb), input ->> 'external_id')
  on conflict ("tenant_id", "channel", "name", "language") do update set
    "inbox_id" = excluded."inbox_id",
    "body" = excluded."body",
    "variables" = excluded."variables",
    "external_id" = excluded."external_id"
  returning * into v_row;
  return to_jsonb(v_row);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.write_knowledge_chunks (
  document_id uuid,
  chunks      jsonb,
  model       text  DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."knowledge_documents"%rowtype;
  v_count integer;
  v_keep boolean;
  v_items jsonb := case when jsonb_typeof(write_knowledge_chunks.chunks) = 'object' then write_knowledge_chunks.chunks -> 'items' else write_knowledge_chunks.chunks end;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."knowledge_documents" x where x."id" = write_knowledge_chunks.document_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai.admin'), false)) then
    raise exception 'document % not found', document_id using errcode = 'P0002', hint = 'KNOWLEDGE_NOT_FOUND';
  end if;
  if coalesce(jsonb_typeof(v_items), '') <> 'array' or jsonb_array_length(v_items) > 10000 then
    raise exception 'chunks must be an array of at most 10000 chunks' using errcode = '22023', hint = 'KNOWLEDGE_CHUNKS';
  end if;
  v_count := jsonb_array_length(v_items);
  v_keep := write_knowledge_chunks.model is not distinct from v_row."embedding_model" or write_knowledge_chunks.model is null;
  insert into "better_supabase"."knowledge_chunks" as t ("document_id", "idx", "content", "token_count", "metadata")
  select v_row."id", (e.ord - 1)::integer, e.value ->> 'content', (e.value ->> 'tokens')::integer, coalesce(e.value -> 'metadata', '{}')
  from jsonb_array_elements(v_items) with ordinality e(value, ord)
  on conflict ("document_id", "idx") do update set
    "content" = excluded."content",
    "token_count" = excluded."token_count",
    "metadata" = excluded."metadata",
    "embedding" = case when v_keep and t."embedding_hash" = md5(excluded."content") then t."embedding" end,
    "embedding_hash" = case when v_keep and t."embedding_hash" = md5(excluded."content") then t."embedding_hash" end;
  delete from "better_supabase"."knowledge_chunks" x where x."document_id" = v_row."id" and x."idx" >= v_count;
  update "better_supabase"."knowledge_documents" x set
    "status" = case when exists (select 1 from "better_supabase"."knowledge_chunks" p where p."document_id" = x."id" and p."embedding" is null) then 'pending' else 'ready' end,
    "error" = null,
    "chunk_count" = v_count,
    "embedding_model" = coalesce(write_knowledge_chunks.model, x."embedding_model"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  if v_row."status" = 'pending' then
  perform "better_supabase"."enqueue_job"(queue => 'knowledge_embed', payload => jsonb_build_object('document_id', v_row."id"), dedupe_key => 'knowledge:' || v_row."id"::text, dedupe_running => false);
  end if;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'scope', v_row."scope", 'scope_id', v_row."scope_id", 'file_id', v_row."file_id", 'title', v_row."title", 'source', v_row."source", 'metadata', v_row."metadata", 'status', v_row."status", 'error', v_row."error", 'chunk_count', v_row."chunk_count", 'embedding_model', v_row."embedding_model", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

ALTER TABLE "better_supabase"."team_members"
  ADD CONSTRAINT "team_members_membership_fkey" FOREIGN KEY (tenant_id, user_id) REFERENCES public.memberships(organization_id, user_id);

ALTER TABLE "better_supabase"."team_members"
  ADD CONSTRAINT "team_members_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."conversations"
  ADD CONSTRAINT "conversations_team_fkey" FOREIGN KEY (team_id) REFERENCES better_supabase.teams(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."team_members"
  ADD CONSTRAINT "team_members_team_id_fkey" FOREIGN KEY (team_id) REFERENCES better_supabase.teams(id) ON DELETE CASCADE;

CREATE INDEX team_members_membership_idx ON better_supabase.team_members USING btree (tenant_id, user_id);

CREATE INDEX team_members_user_idx ON better_supabase.team_members USING btree (user_id);

CREATE POLICY "comments_insert" ON "better_supabase"."comments"
  FOR INSERT
  TO "authenticated"
  WITH
    CHECK
    (((author_id = ( SELECT auth.uid() AS uid)) AND COALESCE(better_supabase.can('tenant'::text, organization_id, 'comments.create'::text), false) AND ( SELECT
    better_supabase.actor_may_write() AS actor_may_write)));

CREATE POLICY "comments_update" ON "better_supabase"."comments"
  FOR UPDATE
  TO "authenticated"
  USING
    ((((author_id = ( SELECT auth.uid() AS uid)) OR (organization_id IN ( SELECT better_supabase.tenant_ids_with('comments.moderate'::text) AS tenant_ids_with))) AND ( SELECT
    better_supabase.actor_may_write() AS actor_may_write)))
  WITH
    CHECK
    ((((author_id = ( SELECT auth.uid() AS uid)) OR (organization_id IN ( SELECT better_supabase.tenant_ids_with('comments.moderate'::text) AS tenant_ids_with))) AND ( SELECT
    better_supabase.actor_may_write() AS actor_may_write)));

CREATE POLICY "bs_notification_recipients_update" ON "better_supabase"."notification_recipients"
  FOR UPDATE
  TO "authenticated"
  USING (((user_id = ( SELECT auth.uid() AS uid)) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)))
  WITH CHECK (((user_id = ( SELECT auth.uid() AS uid)) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));

CREATE POLICY "organization_settings_delete" ON "better_supabase"."organization_settings"
  FOR DELETE
  TO "authenticated"
  USING
    (((organization_id IN ( SELECT better_supabase.tenant_ids_with('settings.update'::text) AS tenant_ids_with)) AND ( SELECT better_supabase.actor_may_write() AS
    actor_may_write)));

CREATE POLICY "organization_settings_insert" ON "better_supabase"."organization_settings"
  FOR INSERT
  TO "authenticated"
  WITH CHECK ((COALESCE(better_supabase.can('tenant'::text, organization_id, 'settings.update'::text), false) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));

CREATE POLICY "organization_settings_update" ON "better_supabase"."organization_settings"
  FOR UPDATE
  TO "authenticated"
  USING
    (((organization_id IN ( SELECT better_supabase.tenant_ids_with('settings.update'::text) AS tenant_ids_with)) AND ( SELECT better_supabase.actor_may_write() AS
    actor_may_write)))
  WITH
    CHECK
    (((organization_id IN ( SELECT better_supabase.tenant_ids_with('settings.update'::text) AS tenant_ids_with)) AND ( SELECT better_supabase.actor_may_write() AS
    actor_may_write)));

CREATE POLICY "platform_settings_delete" ON "better_supabase"."platform_settings"
  FOR DELETE
  TO "authenticated"
  USING ((COALESCE(better_supabase.is_platform('settings.manage'::text), false) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));

CREATE POLICY "platform_settings_insert" ON "better_supabase"."platform_settings"
  FOR INSERT
  TO "authenticated"
  WITH CHECK ((COALESCE(better_supabase.is_platform('settings.manage'::text), false) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));

CREATE POLICY "platform_settings_update" ON "better_supabase"."platform_settings"
  FOR UPDATE
  TO "authenticated"
  USING ((COALESCE(better_supabase.is_platform('settings.manage'::text), false) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)))
  WITH CHECK ((COALESCE(better_supabase.is_platform('settings.manage'::text), false) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));

CREATE POLICY "bs_profiles_update" ON "better_supabase"."profiles"
  FOR UPDATE
  TO "authenticated"
  USING (((id = ( SELECT auth.uid() AS uid)) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)))
  WITH CHECK (((id = ( SELECT auth.uid() AS uid)) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));

CREATE POLICY "push_devices_own_delete" ON "better_supabase"."push_devices"
  FOR DELETE
  TO "authenticated"
  USING (((user_id = ( SELECT auth.uid() AS uid)) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));

CREATE POLICY "team_members_read" ON "better_supabase"."team_members"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('teams.read'::text) AS tenant_ids_with)));

CREATE POLICY "teams_read" ON "better_supabase"."teams"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('teams.read'::text) AS tenant_ids_with)));

CREATE POLICY "bs_inbox_broadcast" ON "realtime"."messages"
  FOR INSERT
  TO "authenticated"
  WITH
    CHECK
    (((extension = ANY (ARRAY['broadcast'::text, 'presence'::text])) AND (( SELECT realtime.topic() AS topic) ~~ ('inbox:'::text || '%'::text)) AND (( SELECT realtime.topic() AS
    topic) !~~ ('inbox:org:'::text || '%'::text)) AND better_supabase.inbox_conversation_allowed(substr(( SELECT realtime.topic() AS topic), 7)) AND
    ( SELECT better_supabase.actor_may_write() AS actor_may_write)));

CREATE POLICY "bs_ai_files_delete" ON "storage"."objects"
  FOR DELETE
  TO "authenticated"
  USING
    (((bucket_id = 'ai-files'::text) AND better_supabase.ai_file_object_allowed(bucket_id, name, 'delete'::text) AND ( SELECT better_supabase.actor_may_write() AS
    actor_may_write)));

CREATE POLICY "bs_ai_files_insert" ON "storage"."objects"
  FOR INSERT
  TO "authenticated"
  WITH
    CHECK
    (((bucket_id = 'ai-files'::text) AND better_supabase.ai_file_object_allowed(bucket_id, name, 'insert'::text) AND ( SELECT better_supabase.actor_may_write() AS
    actor_may_write)));

CREATE POLICY "bs_inbox_files_write" ON "storage"."objects"
  FOR INSERT
  TO "authenticated"
  WITH CHECK (((bucket_id = 'inbox-files'::text) AND better_supabase.inbox_file_allowed(name, true) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));

REVOKE ALL ON FUNCTION "api"."actor_may_write"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."actor_may_write"() TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."raise_actor_readonly"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."raise_actor_readonly"() TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."actor_may_write"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."actor_may_write"() TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."add_team_member"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."add_team_member"(uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."archive_team"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."archive_team"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."create_team"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."create_team"(uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."delete_team"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."delete_team"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_teams"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_teams"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."raise_actor_readonly"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."raise_actor_readonly"() TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."remove_team_member"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."remove_team_member"(uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."team_ids_of"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."team_ids_of"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."update_team"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."update_team"(uuid, text, text) TO "authenticated", "service_role";

GRANT SELECT ON TABLE "better_supabase"."team_members" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."team_members" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."teams" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."teams" TO "service_role";
