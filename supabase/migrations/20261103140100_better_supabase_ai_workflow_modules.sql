SET local check_function_bodies = off;

DROP POLICY "ai_chats_read" ON "better_supabase"."ai_chats";

DROP POLICY "bsb_tenant_scope_select" ON "better_supabase"."ai_chats";

ALTER TABLE "better_supabase"."ai_chat_participants"
  DROP CONSTRAINT "ai_chat_participants_shape_check";

DROP FUNCTION "api"."knowledge_search"(uuid, extensions.vector, text, jsonb, integer, jsonb, uuid[]);

DROP FUNCTION "api"."record_workflow_run"(text, text, text, text, uuid, uuid, jsonb, text, timestamp WITH time zone, timestamp WITH time zone, text, text, text, text, text, text);

DROP FUNCTION "api"."stream_append"(text, integer, text[]);

DROP FUNCTION "better_supabase"."chat_state_delete"(text, text);

DROP FUNCTION "better_supabase"."knowledge_search"(uuid, extensions.vector, text, jsonb, integer, jsonb, uuid[]);

DROP FUNCTION "better_supabase"."record_workflow_run"(text, text, text, text, uuid, uuid, jsonb, text, timestamp WITH time zone, timestamp
  WITH time zone, text, text, text, text, text, text);

DROP FUNCTION "better_supabase"."workflow_open_hooks"(text, text, integer);

CREATE TABLE "better_supabase"."ai_chat_links" (
  "chat_id"    uuid                     NOT NULL,
  "salt"       text                     NOT NULL,
  "created_by" uuid                     NOT NULL,
  "rotated_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "ai_chat_links_pkey" PRIMARY KEY (chat_id),
  CONSTRAINT "ai_chat_links_salt_check" CHECK ((length(salt) >= 16))
);

ALTER TABLE "better_supabase"."ai_chat_links"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "workflow"."workflow_start_hook_admissions" (
  "run_id"             character varying        NOT NULL,
  "token"              character varying        NOT NULL,
  "decision"           character varying        NOT NULL,
  "conflicting_run_id" character varying,
  "created_at"         timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "workflow_start_hook_admissions_pkey" PRIMARY KEY (run_id)
);

ALTER TABLE "workflow"."workflow_start_hook_admissions"
  ENABLE ROW LEVEL SECURITY;

ALTER TABLE "better_supabase"."workflow_runs"
  ADD COLUMN "idempotency_key" text;

ALTER TABLE "better_supabase"."workflow_runs"
  ADD COLUMN "dispatch_until" timestamp WITH time zone;

ALTER TABLE "workflow"."workflow_hooks"
  ADD COLUMN "claims_token" boolean NOT NULL DEFAULT false;

ALTER TABLE "workflow"."workflow_runs"
  ADD COLUMN "start_hook_cbor" bytea;

ALTER TABLE "workflow"."workflow_runs"
  ADD COLUMN "job_prefix" character varying;

ALTER TABLE "workflow"."workflow_events"
  ALTER COLUMN "created_at" DROP DEFAULT;

ALTER TABLE "workflow"."workflow_events"
  ALTER COLUMN "created_at" TYPE timestamp WITH time zone USING "created_at"::timestamp WITH time zone;

ALTER TABLE "workflow"."workflow_events"
  ALTER COLUMN "created_at" SET DEFAULT now();

ALTER TABLE "workflow"."workflow_hooks"
  ALTER COLUMN "created_at" DROP DEFAULT;

ALTER TABLE "workflow"."workflow_hooks"
  ALTER COLUMN "created_at" TYPE timestamp WITH time zone USING "created_at"::timestamp WITH time zone;

ALTER TABLE "workflow"."workflow_hooks"
  ALTER COLUMN "created_at" SET DEFAULT now();

ALTER TABLE "workflow"."workflow_invocations"
  ALTER COLUMN "created_at" DROP DEFAULT;

ALTER TABLE "workflow"."workflow_invocations"
  ALTER COLUMN "created_at" TYPE timestamp WITH time zone USING "created_at"::timestamp WITH time zone;

ALTER TABLE "workflow"."workflow_invocations"
  ALTER COLUMN "created_at" SET DEFAULT now();

ALTER TABLE "workflow"."workflow_invocations"
  ALTER COLUMN "expired_at" DROP DEFAULT;

ALTER TABLE "workflow"."workflow_invocations"
  ALTER COLUMN "expired_at" TYPE timestamp WITH time zone USING "expired_at"::timestamp WITH time zone;

ALTER TABLE "workflow"."workflow_invocations"
  ALTER COLUMN "responded_at" DROP DEFAULT;

ALTER TABLE "workflow"."workflow_invocations"
  ALTER COLUMN "responded_at" TYPE timestamp WITH time zone USING "responded_at"::timestamp WITH time zone;

ALTER TABLE "workflow"."workflow_runs"
  ALTER COLUMN "completed_at" DROP DEFAULT;

ALTER TABLE "workflow"."workflow_runs"
  ALTER COLUMN "completed_at" TYPE timestamp WITH time zone USING "completed_at"::timestamp WITH time zone;

ALTER TABLE "workflow"."workflow_runs"
  ALTER COLUMN "created_at" DROP DEFAULT;

ALTER TABLE "workflow"."workflow_runs"
  ALTER COLUMN "created_at" TYPE timestamp WITH time zone USING "created_at"::timestamp WITH time zone;

ALTER TABLE "workflow"."workflow_runs"
  ALTER COLUMN "created_at" SET DEFAULT now();

ALTER TABLE "workflow"."workflow_runs"
  ALTER COLUMN "expired_at" DROP DEFAULT;

ALTER TABLE "workflow"."workflow_runs"
  ALTER COLUMN "expired_at" TYPE timestamp WITH time zone USING "expired_at"::timestamp WITH time zone;

ALTER TABLE "workflow"."workflow_runs"
  ALTER COLUMN "started_at" DROP DEFAULT;

ALTER TABLE "workflow"."workflow_runs"
  ALTER COLUMN "started_at" TYPE timestamp WITH time zone USING "started_at"::timestamp WITH time zone;

ALTER TABLE "workflow"."workflow_runs"
  ALTER COLUMN "updated_at" DROP DEFAULT;

ALTER TABLE "workflow"."workflow_runs"
  ALTER COLUMN "updated_at" TYPE timestamp WITH time zone USING "updated_at"::timestamp WITH time zone;

ALTER TABLE "workflow"."workflow_runs"
  ALTER COLUMN "updated_at" SET DEFAULT now();

ALTER TABLE "workflow"."workflow_snapshots"
  ALTER COLUMN "created_at" DROP DEFAULT;

ALTER TABLE "workflow"."workflow_snapshots"
  ALTER COLUMN "created_at" TYPE timestamp WITH time zone USING "created_at"::timestamp WITH time zone;

ALTER TABLE "workflow"."workflow_snapshots"
  ALTER COLUMN "created_at" SET DEFAULT now();

ALTER TABLE "workflow"."workflow_steps"
  ALTER COLUMN "completed_at" DROP DEFAULT;

ALTER TABLE "workflow"."workflow_steps"
  ALTER COLUMN "completed_at" TYPE timestamp WITH time zone USING "completed_at"::timestamp WITH time zone;

ALTER TABLE "workflow"."workflow_steps"
  ALTER COLUMN "created_at" DROP DEFAULT;

ALTER TABLE "workflow"."workflow_steps"
  ALTER COLUMN "created_at" TYPE timestamp WITH time zone USING "created_at"::timestamp WITH time zone;

ALTER TABLE "workflow"."workflow_steps"
  ALTER COLUMN "created_at" SET DEFAULT now();

ALTER TABLE "workflow"."workflow_steps"
  ALTER COLUMN "retry_after" DROP DEFAULT;

ALTER TABLE "workflow"."workflow_steps"
  ALTER COLUMN "retry_after" TYPE timestamp WITH time zone USING "retry_after"::timestamp WITH time zone;

ALTER TABLE "workflow"."workflow_steps"
  ALTER COLUMN "started_at" DROP DEFAULT;

ALTER TABLE "workflow"."workflow_steps"
  ALTER COLUMN "started_at" TYPE timestamp WITH time zone USING "started_at"::timestamp WITH time zone;

ALTER TABLE "workflow"."workflow_steps"
  ALTER COLUMN "updated_at" DROP DEFAULT;

ALTER TABLE "workflow"."workflow_steps"
  ALTER COLUMN "updated_at" TYPE timestamp WITH time zone USING "updated_at"::timestamp WITH time zone;

ALTER TABLE "workflow"."workflow_steps"
  ALTER COLUMN "updated_at" SET DEFAULT now();

ALTER TABLE "workflow"."workflow_stream_chunks"
  ALTER COLUMN "created_at" DROP DEFAULT;

ALTER TABLE "workflow"."workflow_stream_chunks"
  ALTER COLUMN "created_at" TYPE timestamp WITH time zone USING "created_at"::timestamp WITH time zone;

ALTER TABLE "workflow"."workflow_stream_chunks"
  ALTER COLUMN "created_at" SET DEFAULT now();

ALTER TABLE "workflow"."workflow_waits"
  ALTER COLUMN "completed_at" DROP DEFAULT;

ALTER TABLE "workflow"."workflow_waits"
  ALTER COLUMN "completed_at" TYPE timestamp WITH time zone USING "completed_at"::timestamp WITH time zone;

ALTER TABLE "workflow"."workflow_waits"
  ALTER COLUMN "created_at" DROP DEFAULT;

ALTER TABLE "workflow"."workflow_waits"
  ALTER COLUMN "created_at" TYPE timestamp WITH time zone USING "created_at"::timestamp WITH time zone;

ALTER TABLE "workflow"."workflow_waits"
  ALTER COLUMN "created_at" SET DEFAULT now();

ALTER TABLE "workflow"."workflow_waits"
  ALTER COLUMN "resume_at" DROP DEFAULT;

ALTER TABLE "workflow"."workflow_waits"
  ALTER COLUMN "resume_at" TYPE timestamp WITH time zone USING "resume_at"::timestamp WITH time zone;

ALTER TABLE "workflow"."workflow_waits"
  ALTER COLUMN "updated_at" DROP DEFAULT;

ALTER TABLE "workflow"."workflow_waits"
  ALTER COLUMN "updated_at" TYPE timestamp WITH time zone USING "updated_at"::timestamp WITH time zone;

ALTER TABLE "workflow"."workflow_waits"
  ALTER COLUMN "updated_at" SET DEFAULT now();

CREATE OR REPLACE FUNCTION api.add_ai_chat_party (
  chat             uuid,
  party_kind       text,
  party            text,
  participant_role text DEFAULT 'viewer'::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."add_ai_chat_party"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.ai_chat_share_summaries (
  chats uuid[]
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."ai_chat_share_summaries"($1) $function$;

CREATE OR REPLACE FUNCTION api.claim_workflow_run_dispatch (
  run   uuid,
  lease integer DEFAULT 60
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."claim_workflow_run_dispatch"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.create_ai_chat_link (
  chat uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."create_ai_chat_link"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_ai_chat_by_link (
  token text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_ai_chat_by_link"($1) $function$;

CREATE OR REPLACE FUNCTION api.knowledge_search (
  tenant          uuid,
  query_embedding extensions.vector DEFAULT NULL::extensions.vector,
  query_text      text              DEFAULT NULL::text,
  scopes          jsonb             DEFAULT NULL::jsonb,
  k               integer           DEFAULT 8,
  filter          jsonb             DEFAULT NULL::jsonb,
  collections     uuid[]            DEFAULT NULL::uuid[],
  priority_order  boolean           DEFAULT true
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."knowledge_search"($1, $2, $3, $4, $5, $6, $7, $8) $function$;

CREATE OR REPLACE FUNCTION api.record_workflow_run (
  engine          text,
  external_id     text,
  definition      text,
  status          text,
  tenant          uuid                     DEFAULT NULL::uuid,
  actor           uuid                     DEFAULT NULL::uuid,
  attributes      jsonb                    DEFAULT '{}'::jsonb,
  error           text                     DEFAULT NULL::text,
  started_at      timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  completed_at    timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  subject_type    text                     DEFAULT NULL::text,
  subject_id      text                     DEFAULT NULL::text,
  principal_kind  text                     DEFAULT NULL::text,
  principal_id    text                     DEFAULT NULL::text,
  mode            text                     DEFAULT NULL::text,
  trigger_node    text                     DEFAULT NULL::text,
  idempotency_key text                     DEFAULT NULL::text
)
  RETURNS uuid
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."record_workflow_run"($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17) $function$;

CREATE OR REPLACE FUNCTION api.remove_ai_chat_party (
  chat       uuid,
  party_kind text,
  party      text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."remove_ai_chat_party"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.revoke_ai_chat_link (
  chat uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."revoke_ai_chat_link"($1) $function$;

CREATE OR REPLACE FUNCTION api.rotate_ai_chat_link (
  chat uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."rotate_ai_chat_link"($1) $function$;

CREATE OR REPLACE FUNCTION api.set_workflow_run_engine (
  run         uuid,
  engine      text,
  external_id text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_workflow_run_engine"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.stream_append (
  stream_id text,
  from_idx  integer,
  chunks    bytea[]
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."stream_append"($1, $2, $3) $function$;

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
  return jsonb_build_object('id', v_row."id", 'chat_id', v_row."chat_id", 'user_id', v_row."user_id", 'kind', v_row."kind", 'team_id', v_row."team_id", 'customer_user_id', v_row."customer_user_id", 'email', v_row."email", 'role', v_row."role", 'added_by', v_row."added_by", 'created_at', v_row."created_at");
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
    insert into "better_supabase"."ai_chat_participants" ("chat_id", "kind", "customer_user_id", "role", "added_by")
    values (v_chat.id, 'customer', add_ai_chat_party.party::uuid, v_role, auth.uid())
    on conflict ("chat_id", "customer_user_id") where "kind" = 'customer' do update set "role" = excluded."role"
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
  return jsonb_build_object('id', v_row."id", 'chat_id', v_row."chat_id", 'user_id', v_row."user_id", 'kind', v_row."kind", 'team_id', v_row."team_id", 'customer_user_id', v_row."customer_user_id", 'email', v_row."email", 'role', v_row."role", 'added_by', v_row."added_by", 'created_at', v_row."created_at");
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
        or (x."visibility" <> 'private' and exists (select 1 from "better_supabase"."ai_chat_participants" pa where pa."chat_id" = x."id" and ((((pa."kind"::text = 'user' and pa."user_id" = (select auth.uid())) or (pa."kind"::text = 'team' and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = pa."team_id"::text and tm."user_id" = (select auth.uid())))) and (x."organization_id" is null or x."organization_id" in (select better_supabase.member_organization_ids()))) or (pa."kind"::text = 'customer' and pa."customer_user_id" = (select auth.uid()) and ((x."organization_id")::text, ('ai-chat')::text, (x."id"::text)::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g)))))
      )
  );
$function$;

CREATE OR REPLACE FUNCTION better_supabase.ai_chat_share_summaries (
  chats uuid[]
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'chat_id', x."id",
    'users', (
      select coalesce(jsonb_agg(jsonb_build_object('user_id', u.id, 'role', u.role) order by u.ord), '[]'::jsonb)
      from (
        select c."owner_id" as id, 'owner' as role, 0 as ord from "better_supabase"."ai_chats" c where c."id" = x."id"
        union all
        select pa."user_id", pa."role"::text, 1 from "better_supabase"."ai_chat_participants" pa
        where pa."chat_id" = x."id" and pa."kind"::text = 'user'
      ) u
    ),
    'team_count', (select count(*) from "better_supabase"."ai_chat_participants" pa where pa."chat_id" = x."id" and pa."kind"::text = 'team'),
    'has_link', exists (select 1 from "better_supabase"."ai_chat_links" l where l."chat_id" = x."id")
  )), '[]'::jsonb)
  from "better_supabase"."ai_chats" x
  where x."id" = any (coalesce(ai_chat_share_summaries.chats, '{}'::uuid[]))
    and "better_supabase"."ai_chat_can_read"(x."id");
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
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_chat."owner_id" = (select auth.uid()), false) or (v_chat."visibility" <> 'private' and exists (select 1 from "better_supabase"."ai_chat_participants" pa where pa."chat_id" = v_chat."id" and pa."role"::text in ('editor') and ((((pa."kind"::text = 'user' and pa."user_id" = (select auth.uid())) or (pa."kind"::text = 'team' and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = pa."team_id"::text and tm."user_id" = (select auth.uid())))) and (v_chat."organization_id" is null or v_chat."organization_id" in (select better_supabase.member_organization_ids()))) or (pa."kind"::text = 'customer' and pa."customer_user_id" = (select auth.uid()) and ((v_chat."organization_id")::text, ('ai-chat')::text, (v_chat."id"::text)::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g)))))) then
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

CREATE OR REPLACE FUNCTION better_supabase.chat_state_acquire_lock (
  prefix    text,
  thread_id text,
  token     text,
  ttl_ms    bigint
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_lock "better_supabase"."chat_state_locks"%rowtype;
begin
  insert into "better_supabase"."chat_state_locks" as l ("key_prefix", "thread_id", "token", "expires_at")
  values (prefix, thread_id, token, clock_timestamp() + make_interval(secs => greatest(coalesce(ttl_ms, 0), 1) / 1000.0))
  on conflict ("key_prefix", "thread_id") do update
    set "token" = excluded."token", "expires_at" = excluded."expires_at", "updated_at" = clock_timestamp()
    where l."expires_at" <= clock_timestamp()
  returning * into v_lock;
  if not found then
    return null;
  end if;
  return jsonb_build_object('thread_id', v_lock."thread_id", 'token', v_lock."token", 'expires_at', v_lock."expires_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.chat_state_append_to_list (
  prefix     text,
  key        text,
  value      jsonb,
  max_length integer DEFAULT NULL::integer,
  ttl_ms     bigint  DEFAULT NULL::bigint
)
  RETURNS void
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_expires timestamptz;
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('chat_state_list:' || prefix || ':' || key));
  v_expires := coalesce(
    case when ttl_ms is null or ttl_ms <= 0 then null else clock_timestamp() + make_interval(secs => ttl_ms / 1000.0) end,
    (select max(k."expires_at") from "better_supabase"."chat_state_lists" k
     where k."key_prefix" = chat_state_append_to_list.prefix and k."list_key" = chat_state_append_to_list.key)
  );
  insert into "better_supabase"."chat_state_lists" ("key_prefix", "list_key", "value", "expires_at")
  values (prefix, key, value, v_expires);
  if max_length is not null and max_length > 0 then
    delete from "better_supabase"."chat_state_lists" l
    where l."key_prefix" = chat_state_append_to_list.prefix and l."list_key" = chat_state_append_to_list.key
      and l."id" < (
        select k."id" from "better_supabase"."chat_state_lists" k
        where k."key_prefix" = chat_state_append_to_list.prefix and k."list_key" = chat_state_append_to_list.key
        order by k."id" desc
        offset max_length - 1 limit 1
      );
  end if;
  if ttl_ms is not null and ttl_ms > 0 then
    update "better_supabase"."chat_state_lists" l set "expires_at" = v_expires
    where l."key_prefix" = chat_state_append_to_list.prefix and l."list_key" = chat_state_append_to_list.key
      and l."expires_at" is distinct from v_expires;
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.chat_state_delete (
  prefix text,
  key    text
)
  RETURNS void
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  delete from "better_supabase"."chat_state_cache" c where c."key_prefix" = chat_state_delete.prefix and c."cache_key" = chat_state_delete.key;
  delete from "better_supabase"."chat_state_lists" l where l."key_prefix" = chat_state_delete.prefix and l."list_key" = chat_state_delete.key;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.chat_state_dequeue (
  prefix    text,
  thread_id text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_value jsonb;
begin
  delete from "better_supabase"."chat_state_queues" q
  where q."id" = (
    select k."id" from "better_supabase"."chat_state_queues" k
    where k."key_prefix" = chat_state_dequeue.prefix and k."thread_id" = chat_state_dequeue.thread_id
    order by k."id"
    limit 1
    for update skip locked
  )
  returning q."value" into v_value;
  return v_value;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.chat_state_enqueue (
  prefix     text,
  thread_id  text,
  entry      jsonb,
  expires_at timestamp with time zone,
  max_size   integer                  DEFAULT NULL::integer
)
  RETURNS integer
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_depth integer;
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('chat_state_queue:' || prefix || ':' || thread_id));
  delete from "better_supabase"."chat_state_queues" q
  where q."key_prefix" = chat_state_enqueue.prefix and q."thread_id" = chat_state_enqueue.thread_id
    and q."expires_at" <= clock_timestamp();
  insert into "better_supabase"."chat_state_queues" ("key_prefix", "thread_id", "value", "expires_at")
  values (prefix, thread_id, entry, expires_at);
  if max_size is not null and max_size > 0 then
    delete from "better_supabase"."chat_state_queues" q
    where q."key_prefix" = chat_state_enqueue.prefix and q."thread_id" = chat_state_enqueue.thread_id
      and q."id" < (
        select k."id" from "better_supabase"."chat_state_queues" k
        where k."key_prefix" = chat_state_enqueue.prefix and k."thread_id" = chat_state_enqueue.thread_id
        order by k."id" desc
        offset max_size - 1 limit 1
      );
  end if;
  select count(*)::integer into v_depth from "better_supabase"."chat_state_queues" q
  where q."key_prefix" = chat_state_enqueue.prefix and q."thread_id" = chat_state_enqueue.thread_id
    and q."expires_at" > clock_timestamp();
  return v_depth;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.chat_state_extend_lock (
  prefix    text,
  thread_id text,
  token     text,
  ttl_ms    bigint
)
  RETURNS boolean
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  update "better_supabase"."chat_state_locks" l
  set "expires_at" = clock_timestamp() + make_interval(secs => greatest(coalesce(ttl_ms, 0), 1) / 1000.0), "updated_at" = clock_timestamp()
  where l."key_prefix" = chat_state_extend_lock.prefix
    and l."thread_id" = chat_state_extend_lock.thread_id
    and l."token" = chat_state_extend_lock.token
    and l."expires_at" > clock_timestamp();
  return found;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.chat_state_set (
  prefix text,
  key    text,
  value  jsonb,
  ttl_ms bigint DEFAULT NULL::bigint
)
  RETURNS void
  LANGUAGE sql
  SET search_path TO ''
  AS $function$
  insert into "better_supabase"."chat_state_cache" ("key_prefix", "cache_key", "value", "expires_at")
  values (prefix, key, value, case when ttl_ms is null or ttl_ms <= 0 then null else clock_timestamp() + make_interval(secs => ttl_ms / 1000.0) end)
  on conflict ("key_prefix", "cache_key") do update
    set "value" = excluded."value", "expires_at" = excluded."expires_at", "updated_at" = clock_timestamp();
$function$;

CREATE OR REPLACE FUNCTION better_supabase.chat_state_set_if_not_exists (
  prefix text,
  key    text,
  value  jsonb,
  ttl_ms bigint DEFAULT NULL::bigint
)
  RETURNS boolean
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
begin
  insert into "better_supabase"."chat_state_cache" as c ("key_prefix", "cache_key", "value", "expires_at")
  values (prefix, key, value, case when ttl_ms is null or ttl_ms <= 0 then null else clock_timestamp() + make_interval(secs => ttl_ms / 1000.0) end)
  on conflict ("key_prefix", "cache_key") do update
    set "value" = excluded."value", "expires_at" = excluded."expires_at", "updated_at" = clock_timestamp()
    where c."expires_at" is not null and c."expires_at" <= clock_timestamp();
  return found;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.claim_workflow_run_dispatch (
  run   uuid,
  lease integer DEFAULT 60
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."workflow_runs"%rowtype;
begin
  update "better_supabase"."workflow_runs" x set "dispatch_until" = now() + make_interval(secs => greatest(coalesce(lease, 60), 1)), "updated_at" = now()
  where x."id" = run
    and x."status" = 'queued'
    and starts_with(x."external_id", 'pending:')
    and (x."dispatch_until" is null or x."dispatch_until" < now())
  returning * into v_row;
  if not found then
    return null;
  end if;
  return jsonb_build_object(
    'id', v_row."id",
    'engine', v_row."engine",
    'externalId', v_row."external_id",
    'definition', v_row."definition",
    'tenant', v_row."tenant_id",
    'actor', v_row."actor_id",
    'status', v_row."status",
    'attributes', v_row."attributes",
    'error', v_row."error",
    'createdAt', v_row."created_at",
    'updatedAt', v_row."updated_at",
    'startedAt', v_row."started_at",
    'completedAt', v_row."completed_at",
    'cancelRequestedAt', v_row."cancel_requested_at",
    'subjectType', v_row."subject_type",
    'subjectId', v_row."subject_id",
    'principalKind', v_row."principal_kind",
    'principalId', v_row."principal_id",
    'mode', v_row."mode",
    'triggerNode', v_row."trigger_node",
    'idempotencyKey', v_row."idempotency_key"
  );
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
  if v_visibility = 'organization' and create_ai_chat.tenant is null then
    raise exception 'A chat outside a tenant stays private' using errcode = '22023', hint = 'AI_CHAT_NO_TENANT';
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
    return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'project_id', v_row."project_id", 'agent_id', v_row."agent_id", 'title', v_row."title", 'model', v_row."model", 'visibility', v_row."visibility", 'mode', v_row."mode", 'pinned', v_row."pinned", 'archived_at', v_row."archived_at", 'is_temporary', v_row."is_temporary", 'expires_at', v_row."expires_at", 'current_leaf_id', v_row."current_leaf_id", 'active_stream_id', v_row."active_stream_id", 'active_run_id', v_row."active_run_id", 'last_message_at', v_row."last_message_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
  end if;
  if v_project is not null and not exists (select 1 from "better_supabase"."ai_projects" pr where pr."id" = v_project and pr."owner_id" = v_owner and pr."organization_id" is not distinct from create_ai_chat.tenant) then
    raise exception 'No project %', v_project using errcode = 'P0002', hint = 'AI_PROJECT_NOT_FOUND';
  end if;
  insert into "better_supabase"."ai_chats" ("id", "organization_id", "owner_id", "project_id", "agent_id", "title", "model", "visibility", "mode", "is_temporary", "expires_at")
  values (
    v_id, create_ai_chat.tenant, v_owner, v_project, v_fields ->> 'agent_id',
    coalesce(v_fields ->> 'title', ''), v_fields ->> 'model', v_visibility, v_fields ->> 'mode', v_temporary,
    case when v_temporary then now() + interval '1 day' end
  )
  returning * into v_row;
  if not v_temporary then
    perform "better_supabase"."ai_chat_notify"(v_id, v_owner, 'chat.created', '{}'::jsonb, true);
  end if;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'project_id', v_row."project_id", 'agent_id', v_row."agent_id", 'title', v_row."title", 'model', v_row."model", 'visibility', v_row."visibility", 'mode', v_row."mode", 'pinned', v_row."pinned", 'archived_at', v_row."archived_at", 'is_temporary', v_row."is_temporary", 'expires_at', v_row."expires_at", 'current_leaf_id', v_row."current_leaf_id", 'active_stream_id', v_row."active_stream_id", 'active_run_id', v_row."active_run_id", 'last_message_at', v_row."last_message_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_ai_chat_link (
  chat uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_chat record;
  v_salt text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."id" as id, x."owner_id" as owner, x."organization_id" as tenant into v_chat
  from "better_supabase"."ai_chats" x where x."id" = create_ai_chat_link.chat for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_chat.owner = (select auth.uid()), false)) then
    raise exception 'No chat %', create_ai_chat_link.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and not coalesce(better_supabase.can('tenant', v_chat.tenant, 'ai_chat.share'), false) then
    raise exception 'You may not share chats here' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  insert into "better_supabase"."ai_chat_links" ("chat_id", "salt", "created_by")
  values (v_chat.id, encode(extensions.gen_random_bytes(16), 'hex'), coalesce(auth.uid(), v_chat.owner))
  on conflict ("chat_id") do nothing;
  select l."salt" into v_salt from "better_supabase"."ai_chat_links" l where l."chat_id" = v_chat.id;
  update "better_supabase"."ai_chats" c set "visibility" = 'shared', "updated_at" = now()
  where c."id" = v_chat.id and c."visibility" = 'private';
  return jsonb_build_object('chat_id', v_chat.id, 'token', v_chat.id::text || '.' || encode(extensions.digest(convert_to(v_salt || v_chat.id::text, 'utf8'), 'sha256'), 'hex'));
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
    ('user', 'better_supabase.moderation_notices', '"better_supabase"."moderation_notices"', 'notifier_id', true, '{}'::text[], true),
    ('user', 'better_supabase.moderation_flaggers', '"better_supabase"."moderation_flaggers"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.moderation_appeals', '"better_supabase"."moderation_appeals"', 'appellant_id', true, '{}'::text[], true),
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
    ('user', 'better_supabase.shift_swaps', '"better_supabase"."shift_swaps"', 'from_user_id', true, '{}'::text[], true),
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
    ('user', 'better_supabase.appraisals', '"better_supabase"."appraisals"', 'subject_user_id', true, '{}'::text[], true),
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

CREATE OR REPLACE FUNCTION better_supabase.enqueue_job (
  queue          text,
  payload        jsonb   DEFAULT '{}'::jsonb,
  delay          integer DEFAULT 0,
  max_attempts   integer DEFAULT 5,
  dedupe_key     text    DEFAULT NULL::text,
  dedupe_running boolean DEFAULT true
)
  RETURNS bigint
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  existing bigint;
begin
  perform better_supabase.ensure_job_queue(queue);
  if dedupe_key is not null then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(queue), pg_catalog.hashtext(dedupe_key));
    execute format('select msg_id from pgmq.%I where message ? ''dedupe_key'' and message ->> ''dedupe_key'' = $1 and ($2 or read_ct = 0) limit 1', 'q_' || queue)
      into existing using dedupe_key, dedupe_running;
    if existing is not null then
      -- A message nobody has read yet moves earlier when this enqueue is due
      -- sooner, never later.
      execute format('update pgmq.%I set vt = least(vt, clock_timestamp() + make_interval(secs => $2)) where msg_id = $1 and read_ct = 0', 'q_' || queue)
        using existing, greatest(delay, 0);
      return existing;
    end if;
  end if;
  return (
    select pgmq.send(
      queue,
      jsonb_build_object('payload', payload, 'max_attempts', max_attempts)
        || case when dedupe_key is null then '{}'::jsonb else jsonb_build_object('dedupe_key', dedupe_key) end,
      greatest(delay, 0)
    )
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_ai_chat (
  chat uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."ai_chats";
begin
  if not "better_supabase"."ai_chat_can_read"(get_ai_chat.chat) then
    raise exception 'No chat %', get_ai_chat.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  select * into v_row from "better_supabase"."ai_chats" x where x."id" = get_ai_chat.chat;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'project_id', v_row."project_id", 'agent_id', v_row."agent_id", 'title', v_row."title", 'model', v_row."model", 'visibility', v_row."visibility", 'mode', v_row."mode", 'pinned', v_row."pinned", 'archived_at', v_row."archived_at", 'is_temporary', v_row."is_temporary", 'expires_at', v_row."expires_at", 'current_leaf_id', v_row."current_leaf_id", 'active_stream_id', v_row."active_stream_id", 'active_run_id', v_row."active_run_id", 'last_message_at', v_row."last_message_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_ai_chat_by_link (
  token text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_chat "better_supabase"."ai_chats";
  v_id uuid;
  v_salt text;
begin
  if get_ai_chat_by_link.token is null or get_ai_chat_by_link.token !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.[0-9a-f]{64}$' then
    return null;
  end if;
  v_id := split_part(get_ai_chat_by_link.token, '.', 1)::uuid;
  select l."salt" into v_salt from "better_supabase"."ai_chat_links" l where l."chat_id" = v_id;
  if not found
    or v_id::text || '.' || encode(extensions.digest(convert_to(v_salt || v_id::text, 'utf8'), 'sha256'), 'hex') <> get_ai_chat_by_link.token then
    return null;
  end if;
  select * into v_chat from "better_supabase"."ai_chats" x where x."id" = v_id and x."visibility" <> 'private';
  if not found then
    return null;
  end if;
  return jsonb_build_object(
    'chat', jsonb_build_object('id', v_chat."id", 'title', v_chat."title", 'model', v_chat."model", 'mode', v_chat."mode", 'created_at', v_chat."created_at"),
    'leaf_id', v_chat."current_leaf_id",
    'messages', case when v_chat."current_leaf_id" is null then '[]'::jsonb else "better_supabase"."ai_message_path_of"(v_chat."id", v_chat."current_leaf_id", false) end
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_shared_ai_chat (
  token text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_share "better_supabase"."ai_chat_shares";
  v_chat "better_supabase"."ai_chats";
begin
  if get_shared_ai_chat.token is null or get_shared_ai_chat.token !~ '^[0-9a-f]{64}$' then
    return null;
  end if;
  select * into v_share from "better_supabase"."ai_chat_shares" x
  where x."token_hash" = encode(sha256(convert_to(get_shared_ai_chat.token, 'UTF8')), 'hex') and x."revoked_at" is null;
  if not found then
    return null;
  end if;
  select * into v_chat from "better_supabase"."ai_chats" x where x."id" = v_share."chat_id";
  return jsonb_build_object(
    'chat', jsonb_build_object('id', v_chat."id", 'title', v_chat."title", 'model', v_chat."model", 'created_at', v_chat."created_at"),
    'leaf_id', v_share."leaf_id",
    'messages', "better_supabase"."ai_message_path_of"(v_chat."id", v_share."leaf_id", false)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.knowledge_search (
  tenant          uuid,
  query_embedding extensions.vector DEFAULT NULL::extensions.vector,
  query_text      text              DEFAULT NULL::text,
  scopes          jsonb             DEFAULT NULL::jsonb,
  k               integer           DEFAULT 8,
  filter          jsonb             DEFAULT NULL::jsonb,
  collections     uuid[]            DEFAULT NULL::uuid[],
  priority_order  boolean           DEFAULT true
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  previous_scan text := current_setting('hnsw.iterative_scan', true);
  v_candidates integer := least(greatest(knowledge_search.k, 1) * 4, 400);
  v_scopes jsonb := case when jsonb_typeof(knowledge_search.scopes) = 'object' then knowledge_search.scopes -> 'items' else knowledge_search.scopes end;
  v_rows jsonb;
begin
  perform set_config('hnsw.iterative_scan', 'relaxed_order', true);
  with docs as materialized (
    select x."id" as id, x."organization_id" as doc_tenant, x."title" as title, coalesce((select kc."priority" from "better_supabase"."knowledge_collections" kc where kc."id" = x."collection_id"), 0) as priority from "better_supabase"."knowledge_documents" x
    where (x."organization_id" = knowledge_search.tenant or x."organization_id" is null)
      and (x."collection_id" is null or exists (select 1 from "better_supabase"."knowledge_collections" kc where kc."id" = x."collection_id" and kc."visibility" <> 'disabled'))
      and (knowledge_search.collections is null or x."collection_id" = any(knowledge_search.collections))
      and (v_scopes is null or exists (
        select 1 from jsonb_array_elements(v_scopes) s
        where s.value ->> 'scope' = x."scope"
          and (s.value ->> 'scope' = 'subject' or s.value ->> 'id' is null or (s.value ->> 'id')::uuid = x."scope_id")
          and (s.value ->> 'scope' <> 'subject' or ((s.value ->> 'type' is null or s.value ->> 'type' = x."subject_type") and (s.value ->> 'id' is null or s.value ->> 'id' = x."subject_id")))
      ))
      and (knowledge_search.filter is null or x."metadata" @> knowledge_search.filter)
  ),
  vector_hits as materialized (
    select t."document_id" as document_id, t."idx" as idx, t."embedding" operator(extensions.<=>) knowledge_search.query_embedding as distance
    from "better_supabase"."knowledge_chunks" t
    where knowledge_search.query_embedding is not null and t."embedding" is not null
      and t."document_id" in (select docs.id from docs)
    order by t."embedding" operator(extensions.<=>) knowledge_search.query_embedding
    limit v_candidates
  ),
  vector_ranked as (
    select h.document_id, h.idx, row_number() over (order by h.distance) as rank from vector_hits h
  ),
  text_hits as materialized (
    select t."document_id" as document_id, t."idx" as idx, ts_rank_cd(t."tsv", q) as text_score
    from "better_supabase"."knowledge_chunks" t, websearch_to_tsquery('simple'::regconfig, knowledge_search.query_text) q
    where knowledge_search.query_text is not null and t."tsv" @@ q
      and t."document_id" in (select docs.id from docs)
    order by text_score desc
    limit v_candidates
  ),
  text_ranked as (
    select x.document_id, x.idx, row_number() over (order by x.text_score desc) as rank from text_hits x
  ),
  fused as (
    select coalesce(v.document_id, x.document_id) as document_id, coalesce(v.idx, x.idx) as idx,
      coalesce(1.0 / (60 + v.rank), 0) + coalesce(1.0 / (60 + x.rank), 0) as score
    from vector_ranked v full join text_ranked x on x.document_id = v.document_id and x.idx = v.idx
  )
  select coalesce(jsonb_agg(jsonb_build_object('document_id', r.document_id, 'idx', r.idx, 'chunk_id', r.document_id::text || '#' || r.idx::text, 'organization_id', r.doc_tenant, 'content', r.content, 'metadata', r.metadata, 'title', r.title, 'score', r.score) order by r.rank_priority desc, r.score desc, r.document_id, r.idx), '[]')
  into v_rows
  from (
    select f.document_id, f.idx, t."content" as content, t."metadata" as metadata, docs.title, docs.doc_tenant,
      case when knowledge_search.priority_order then docs.priority else 0 end as rank_priority, f.score
    from fused f
    join "better_supabase"."knowledge_chunks" t on t."document_id" = f.document_id and t."idx" = f.idx
    join docs on docs.id = f.document_id
    order by rank_priority desc, f.score desc, f.document_id, f.idx
    limit least(greatest(knowledge_search.k, 1), 100)
  ) r;
  perform set_config('hnsw.iterative_scan', coalesce(previous_scan, 'off'), true);
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
    select jsonb_build_array(jsonb_build_object('id', null, 'chat_id', c."id", 'user_id', c."owner_id", 'kind', 'user', 'team_id', null, 'customer_user_id', null, 'email', null, 'role', 'owner', 'added_by', null, 'created_at', c."created_at"))
      || coalesce((
        select jsonb_agg(jsonb_build_object('id', x."id", 'chat_id', x."chat_id", 'user_id', x."user_id", 'kind', x."kind", 'team_id', x."team_id", 'customer_user_id', x."customer_user_id", 'email', x."email", 'role', x."role", 'added_by', x."added_by", 'created_at', x."created_at") order by x."created_at", x."id")
        from "better_supabase"."ai_chat_participants" x
        where x."chat_id" = list_ai_chat_participants.chat
      ), '[]'::jsonb)
    from "better_supabase"."ai_chats" c where c."id" = list_ai_chat_participants.chat
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_ai_chat_shares (
  chat uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', x."id", 'leaf_id', x."leaf_id", 'created_by', x."created_by",
    'created_at', x."created_at", 'revoked_at', x."revoked_at"
  ) order by x."created_at" desc), '[]'::jsonb)
  from "better_supabase"."ai_chat_shares" x
  join "better_supabase"."ai_chats" c on c."id" = x."chat_id"
  where x."chat_id" = list_ai_chat_shares.chat
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or c."owner_id" = (select auth.uid()));
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
    where (x."owner_id" = v_uid or (x."visibility" <> 'private' and exists (select 1 from "better_supabase"."ai_chat_participants" pa where pa."chat_id" = x."id" and ((((pa."kind"::text = 'user' and pa."user_id" = (select auth.uid())) or (pa."kind"::text = 'team' and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = pa."team_id"::text and tm."user_id" = (select auth.uid())))) and (x."organization_id" is null or x."organization_id" in (select better_supabase.member_organization_ids()))) or (pa."kind"::text = 'customer' and pa."customer_user_id" = (select auth.uid()) and ((x."organization_id")::text, ('ai-chat')::text, (x."id"::text)::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g))))))
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

CREATE OR REPLACE FUNCTION better_supabase.record_workflow_run (
  engine          text,
  external_id     text,
  definition      text,
  status          text,
  tenant          uuid                     DEFAULT NULL::uuid,
  actor           uuid                     DEFAULT NULL::uuid,
  attributes      jsonb                    DEFAULT '{}'::jsonb,
  error           text                     DEFAULT NULL::text,
  started_at      timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  completed_at    timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  subject_type    text                     DEFAULT NULL::text,
  subject_id      text                     DEFAULT NULL::text,
  principal_kind  text                     DEFAULT NULL::text,
  principal_id    text                     DEFAULT NULL::text,
  mode            text                     DEFAULT NULL::text,
  trigger_node    text                     DEFAULT NULL::text,
  idempotency_key text                     DEFAULT NULL::text
)
  RETURNS uuid
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_id uuid;
begin
  if idempotency_key is not null then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('workflow_run_key'), pg_catalog.hashtext(coalesce(tenant::text, '') || ':' || idempotency_key));
    select x."id" into v_id from "better_supabase"."workflow_runs" x
    where x."tenant_id" is not distinct from tenant
      and x."idempotency_key" = idempotency_key
      and not (x."engine" = engine and x."external_id" = external_id);
    if found then
      return v_id;
    end if;
  end if;
  insert into "better_supabase"."workflow_runs" as x ("engine", "external_id", "definition", "status", "tenant_id", "actor_id", "attributes", "error", "started_at", "completed_at", "subject_type", "subject_id", "principal_kind", "principal_id", "mode", "trigger_node", "idempotency_key")
  values (engine, external_id, definition, status, tenant, actor, coalesce(attributes, '{}'::jsonb), left(error, 4000), started_at, completed_at, subject_type, subject_id, principal_kind, principal_id, coalesce(mode, 'live'), trigger_node, idempotency_key)
  on conflict on constraint workflow_runs_engine_external_key do update set
    "definition" = excluded."definition",
    "status" = excluded."status",
    "tenant_id" = coalesce(x."tenant_id", excluded."tenant_id"),
    "actor_id" = coalesce(x."actor_id", excluded."actor_id"),
    "attributes" = x."attributes" || excluded."attributes",
    "error" = coalesce(excluded."error", x."error"),
    "started_at" = coalesce(x."started_at", excluded."started_at"),
    "completed_at" = coalesce(excluded."completed_at", x."completed_at"),
    "subject_type" = case when x."subject_type" is null then excluded."subject_type" else x."subject_type" end,
    "subject_id" = case when x."subject_type" is null then excluded."subject_id" else x."subject_id" end,
    "principal_kind" = case when x."principal_kind" is null then excluded."principal_kind" else x."principal_kind" end,
    "principal_id" = case when x."principal_kind" is null then excluded."principal_id" else x."principal_id" end,
    "trigger_node" = coalesce(x."trigger_node", excluded."trigger_node"),
    "idempotency_key" = coalesce(x."idempotency_key", excluded."idempotency_key"),
    "updated_at" = now()
  returning x."id" into v_id;
  return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.remove_ai_chat_participant (
  chat        uuid,
  participant uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_owner uuid;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."owner_id" into v_owner from "better_supabase"."ai_chats" x where x."id" = remove_ai_chat_participant.chat;
  if not found or not (
    coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
    or coalesce(v_owner = (select auth.uid()), false)
    or coalesce(remove_ai_chat_participant.participant = (select auth.uid()), false)
  ) then
    raise exception 'No chat %', remove_ai_chat_participant.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  delete from "better_supabase"."ai_chat_participants" x
  where x."chat_id" = remove_ai_chat_participant.chat and x."user_id" = remove_ai_chat_participant.participant and x."kind"::text = 'user';
  get diagnostics v_count = row_count;
  if v_count > 0 then
    perform "better_supabase"."ai_chat_notify"(remove_ai_chat_participant.chat, remove_ai_chat_participant.participant, 'participant.removed', jsonb_build_object('userId', remove_ai_chat_participant.participant), true);
  end if;
  return v_count > 0;
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
    and ((remove_ai_chat_party.party_kind = 'team' and x."team_id" = remove_ai_chat_party.party::uuid) or (remove_ai_chat_party.party_kind = 'customer' and x."customer_user_id" = remove_ai_chat_party.party::uuid) or (remove_ai_chat_party.party_kind = 'external' and lower(x."email") = lower(btrim(remove_ai_chat_party.party))));
  get diagnostics v_count = row_count;
  if v_count > 0 then
    perform "better_supabase"."ai_chat_notify"(v_chat.id, v_chat.owner, 'participant.removed', jsonb_build_object('kind', remove_ai_chat_party.party_kind), true);
  end if;
  return v_count > 0;
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
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_chat."owner_id" = (select auth.uid()), false) or (v_chat."visibility" <> 'private' and exists (select 1 from "better_supabase"."ai_chat_participants" pa where pa."chat_id" = v_chat."id" and pa."role"::text in ('editor') and ((((pa."kind"::text = 'user' and pa."user_id" = (select auth.uid())) or (pa."kind"::text = 'team' and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = pa."team_id"::text and tm."user_id" = (select auth.uid())))) and (v_chat."organization_id" is null or v_chat."organization_id" in (select better_supabase.member_organization_ids()))) or (pa."kind"::text = 'customer' and pa."customer_user_id" = (select auth.uid()) and ((v_chat."organization_id")::text, ('ai-chat')::text, (v_chat."id"::text)::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g)))))) then
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
    or (v_run."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_run."tenant_id", 'workflows.manage'), false))) then
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
    'cancelRequestedAt', v_run."cancel_requested_at",
    'subjectType', v_run."subject_type",
    'subjectId', v_run."subject_id",
    'principalKind', v_run."principal_kind",
    'principalId', v_run."principal_id",
    'mode', v_run."mode",
    'triggerNode', v_run."trigger_node",
    'idempotencyKey', v_run."idempotency_key"
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
    'cancelRequestedAt', v_run."cancel_requested_at",
    'subjectType', v_run."subject_type",
    'subjectId', v_run."subject_id",
    'principalKind', v_run."principal_kind",
    'principalId', v_run."principal_id",
    'mode', v_run."mode",
    'triggerNode', v_run."trigger_node",
    'idempotencyKey', v_run."idempotency_key"
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.revoke_ai_chat_link (
  chat uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_chat record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."id" as id, x."owner_id" as owner, x."organization_id" as tenant into v_chat
  from "better_supabase"."ai_chats" x where x."id" = revoke_ai_chat_link.chat for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_chat.owner = (select auth.uid()), false)) then
    raise exception 'No chat %', revoke_ai_chat_link.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  delete from "better_supabase"."ai_chat_links" l where l."chat_id" = v_chat.id;
  return found;
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
  perform "better_supabase".emit_event('ai_chat.share_revoked', jsonb_build_object('chatId', v_chat."id", 'shareId', revoke_ai_chat_share.id, 'organizationId', v_chat."organization_id"::text, 'ownerId', v_chat."owner_id"), 'ai-chats/' || v_chat."id"::text, (v_chat."organization_id")::text, null, 'better-supabase/ai-chat');
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

CREATE OR REPLACE FUNCTION better_supabase.rotate_ai_chat_link (
  chat uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_chat record;
  v_salt text := encode(extensions.gen_random_bytes(16), 'hex');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."id" as id, x."owner_id" as owner, x."organization_id" as tenant into v_chat
  from "better_supabase"."ai_chats" x where x."id" = rotate_ai_chat_link.chat for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_chat.owner = (select auth.uid()), false)) then
    raise exception 'No chat %', rotate_ai_chat_link.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and not coalesce(better_supabase.can('tenant', v_chat.tenant, 'ai_chat.share'), false) then
    raise exception 'You may not share chats here' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  update "better_supabase"."ai_chat_links" l set "salt" = v_salt, "rotated_at" = now()
  where l."chat_id" = v_chat.id;
  if not found then
    raise exception 'Chat % has no link', v_chat.id using errcode = 'P0002', hint = 'AI_CHAT_NO_LINK';
  end if;
  return jsonb_build_object('chat_id', v_chat.id, 'token', v_chat.id::text || '.' || encode(extensions.digest(convert_to(v_salt || v_chat.id::text, 'utf8'), 'sha256'), 'hex'));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_workflow_run_engine (
  run         uuid,
  engine      text,
  external_id text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."workflow_runs"%rowtype;
  v_other "better_supabase"."workflow_runs"%rowtype;
begin
  select * into v_row from "better_supabase"."workflow_runs" x where x."id" = run for update;
  if not found then
    return null;
  end if;
  select * into v_other from "better_supabase"."workflow_runs" x
  where x."engine" = engine and x."external_id" = external_id and x."id" <> run
  for update;
  if found then
    delete from "better_supabase"."workflow_runs" x where x."id" = run;
    update "better_supabase"."workflow_runs" x set "idempotency_key" = coalesce(x."idempotency_key", v_row."idempotency_key"),
      "attributes" = v_row."attributes" || x."attributes",
      "tenant_id" = coalesce(x."tenant_id", v_row."tenant_id"),
      "actor_id" = coalesce(x."actor_id", v_row."actor_id"),
      "updated_at" = now()
    where x."id" = v_other."id"
    returning * into v_row;
    return jsonb_build_object(
    'id', v_row."id",
    'engine', v_row."engine",
    'externalId', v_row."external_id",
    'definition', v_row."definition",
    'tenant', v_row."tenant_id",
    'actor', v_row."actor_id",
    'status', v_row."status",
    'attributes', v_row."attributes",
    'error', v_row."error",
    'createdAt', v_row."created_at",
    'updatedAt', v_row."updated_at",
    'startedAt', v_row."started_at",
    'completedAt', v_row."completed_at",
    'cancelRequestedAt', v_row."cancel_requested_at",
    'subjectType', v_row."subject_type",
    'subjectId', v_row."subject_id",
    'principalKind', v_row."principal_kind",
    'principalId', v_row."principal_id",
    'mode', v_row."mode",
    'triggerNode', v_row."trigger_node",
    'idempotencyKey', v_row."idempotency_key"
  );
  end if;
  update "better_supabase"."workflow_runs" x set "engine" = engine, "external_id" = external_id, "dispatch_until" = null, "updated_at" = now()
  where x."id" = run
  returning * into v_row;
  return jsonb_build_object(
    'id', v_row."id",
    'engine', v_row."engine",
    'externalId', v_row."external_id",
    'definition', v_row."definition",
    'tenant', v_row."tenant_id",
    'actor', v_row."actor_id",
    'status', v_row."status",
    'attributes', v_row."attributes",
    'error', v_row."error",
    'createdAt', v_row."created_at",
    'updatedAt', v_row."updated_at",
    'startedAt', v_row."started_at",
    'completedAt', v_row."completed_at",
    'cancelRequestedAt', v_row."cancel_requested_at",
    'subjectType', v_row."subject_type",
    'subjectId', v_row."subject_id",
    'principalKind', v_row."principal_kind",
    'principalId', v_row."principal_id",
    'mode', v_row."mode",
    'triggerNode', v_row."trigger_node",
    'idempotencyKey', v_row."idempotency_key"
  );
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
  perform "better_supabase".emit_event('ai_chat.shared', jsonb_build_object('chatId', v_chat."id", 'shareId', v_id, 'organizationId', v_chat."organization_id"::text, 'ownerId', v_chat."owner_id", 'leafId', v_leaf), 'ai-chats/' || v_chat."id"::text, (v_chat."organization_id")::text, 'ai_chat.shared:' || v_id::text, 'better-supabase/ai-chat');
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

CREATE OR REPLACE FUNCTION better_supabase.stream_append (
  stream_id text,
  from_idx  integer,
  chunks    bytea[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_stream "better_supabase"."streams"%rowtype;
  v_next integer;
  v_wake boolean;
begin
  select * into v_stream from "better_supabase"."streams" where "id" = stream_append.stream_id;
  if not found then
    raise exception 'stream % does not exist', stream_append.stream_id
      using errcode = 'P0002', hint = 'STREAM_NOT_FOUND';
  end if;
  if v_stream."closed_at" is not null then
    raise exception 'stream % is closed', stream_append.stream_id
      using errcode = 'P0001', hint = 'STREAM_CLOSED';
  end if;
  select coalesce(max("idx") + 1, 0) into v_next from "better_supabase"."stream_chunks" where "stream_id" = stream_append.stream_id;
  if from_idx < 0 or from_idx > v_next then
    raise exception 'stream % is at chunk %, not %', stream_append.stream_id, v_next, from_idx
      using errcode = 'P0001', hint = 'STREAM_GAP';
  end if;
  insert into "better_supabase"."stream_chunks" ("stream_id", "idx", "data")
  select stream_append.stream_id, from_idx + (n.ord - 1)::integer, n.chunk
  from unnest(coalesce(chunks, '{}'::bytea[])) with ordinality as n(chunk, ord)
  on conflict do nothing;
  v_next := greatest(v_next, from_idx + coalesce(cardinality(chunks), 0));
  v_wake := v_stream."wake" and coalesce(cardinality(chunks), 0) > 0;
  
  if v_wake and to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send('{}'::jsonb, 'append', 'stream:' || stream_append.stream_id, true);
  end if;
  return jsonb_build_object('next', v_next, 'cancelled', v_stream."cancel_requested_at" is not null);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.stream_read (
  stream_id text,
  from_idx  integer DEFAULT 0,
  max       integer DEFAULT 1000
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_stream "better_supabase"."streams"%rowtype;
  v_chunks text[];
  v_next integer;
  v_last integer;
begin
  select * into v_stream from "better_supabase"."streams" where "id" = stream_read.stream_id;
  if not found then
    return jsonb_build_object('found', false, 'chunks', '[]'::jsonb, 'next', greatest(coalesce(from_idx, 0), 0), 'done', true, 'cancelled', false);
  end if;
  select coalesce(array_agg(replace(encode(r."data", 'base64'), E'
', '') order by r."idx"), '{}'::text[]) into v_chunks
  from (
    select "data", "idx" from "better_supabase"."stream_chunks"
    where "stream_id" = stream_read.stream_id and "idx" >= greatest(coalesce(from_idx, 0), 0)
    order by "idx"
    limit least(greatest(coalesce(max, 1000), 0), 10000)
  ) r;
  v_next := greatest(coalesce(from_idx, 0), 0) + cardinality(v_chunks);
  select coalesce(max("idx") + 1, 0) into v_last from "better_supabase"."stream_chunks" where "stream_id" = stream_read.stream_id;
  return jsonb_build_object(
    'found', true,
    'chunks', to_jsonb(v_chunks),
    'next', v_next,
    'done', v_stream."closed_at" is not null and v_next >= v_last,
    'cancelled', v_stream."cancel_requested_at" is not null
  );
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
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_chat."owner_id" = (select auth.uid()), false) or (v_chat."visibility" <> 'private' and exists (select 1 from "better_supabase"."ai_chat_participants" pa where pa."chat_id" = v_chat."id" and pa."role"::text in ('editor') and ((((pa."kind"::text = 'user' and pa."user_id" = (select auth.uid())) or (pa."kind"::text = 'team' and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = pa."team_id"::text and tm."user_id" = (select auth.uid())))) and (v_chat."organization_id" is null or v_chat."organization_id" in (select better_supabase.member_organization_ids()))) or (pa."kind"::text = 'customer' and pa."customer_user_id" = (select auth.uid()) and ((v_chat."organization_id")::text, ('ai-chat')::text, (v_chat."id"::text)::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g)))))) then
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
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."owner_id" = (select auth.uid()), false)) then
    raise exception 'No chat %', update_ai_chat.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  if v_project is not null and not exists (select 1 from "better_supabase"."ai_projects" pr where pr."id" = v_project and pr."owner_id" = v_row."owner_id" and pr."organization_id" is not distinct from v_row."organization_id") then
    raise exception 'No project %', v_project using errcode = 'P0002', hint = 'AI_PROJECT_NOT_FOUND';
  end if;
  if v_fields ->> 'visibility' = 'organization' and v_row."organization_id" is null then
    raise exception 'A chat outside a tenant stays private' using errcode = '22023', hint = 'AI_CHAT_NO_TENANT';
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
    "mode" = case when v_fields ? 'mode' then v_fields ->> 'mode' else x."mode" end,
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
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'project_id', v_row."project_id", 'agent_id', v_row."agent_id", 'title', v_row."title", 'model', v_row."model", 'visibility', v_row."visibility", 'mode', v_row."mode", 'pinned', v_row."pinned", 'archived_at', v_row."archived_at", 'is_temporary', v_row."is_temporary", 'expires_at', v_row."expires_at", 'current_leaf_id', v_row."current_leaf_id", 'active_stream_id', v_row."active_stream_id", 'active_run_id', v_row."active_run_id", 'last_message_at', v_row."last_message_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.workflow_open_hooks (
  tenant        text    DEFAULT NULL::text,
  workflow_name text    DEFAULT NULL::text,
  max           integer DEFAULT 50
)
  RETURNS TABLE (
    hook_id       text,
    run_id        text,
    workflow      text,
    tenant_id     text,
    actor_id      text,
    metadata      jsonb,
    metadata_cbor bytea,
    created_at    timestamp with time zone
  )
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select h.hook_id::text, h.run_id::text, r.name::text,
    r.attributes ->> 'bsb.tenant', r.attributes ->> 'bsb.actor',
    h.metadata, h.metadata_cbor, h.created_at
  from workflow.workflow_hooks h
  join workflow.workflow_runs r on r.id = h.run_id
  where r.status::text in ('pending', 'running')
    and not coalesce(h.is_system, false)
    and (workflow_open_hooks.tenant is null or r.attributes ->> 'bsb.tenant' = workflow_open_hooks.tenant)
    and (workflow_open_hooks.workflow_name is null or r.name = workflow_open_hooks.workflow_name)
  order by h.created_at desc
  limit least(greatest(coalesce(workflow_open_hooks.max, 50), 1), 500);
$function$;

CREATE OR REPLACE FUNCTION better_supabase.workflow_purge_runs (
  older_than interval DEFAULT '30 days'::interval,
  statuses   text[]   DEFAULT ARRAY['completed'::text,
  'failed'::text,
  'cancelled'::text],
  batch      integer  DEFAULT 500
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_statuses text[] := coalesce(statuses, array['completed', 'failed', 'cancelled']);
  v_ids text[];
  v_count integer;
begin
  if exists (select 1 from unnest(v_statuses) s where s not in ('completed', 'failed', 'cancelled')) then
    raise exception 'workflow_purge_runs deletes only completed, failed or cancelled runs'
      using errcode = '22023', hint = 'WORKFLOW_PURGE_STATUS';
  end if;
  select coalesce(array_agg(x.id), '{}') into v_ids from (
    select r.id from workflow.workflow_runs r
    where r.status::text = any (v_statuses)
      and coalesce(r.completed_at, r.updated_at) < now() - coalesce(older_than, interval '30 days')
    order by coalesce(r.completed_at, r.updated_at)
    limit least(greatest(coalesce(batch, 500), 1), 10000)
    for update skip locked
  ) x;
  if cardinality(v_ids) = 0 then
    return 0;
  end if;
  delete from workflow.workflow_events where run_id = any (v_ids);
  delete from workflow.workflow_event_slots where run_id = any (v_ids);
  delete from workflow.workflow_steps where run_id = any (v_ids);
  delete from workflow.workflow_waits where run_id = any (v_ids);
  delete from workflow.workflow_stream_chunks where run_id = any (v_ids);
  delete from workflow.workflow_snapshots where run_id = any (v_ids);
  delete from workflow.workflow_invocations where run_id = any (v_ids);
  delete from workflow.workflow_hooks
    where run_id = any (v_ids) and (token_retention_until is null or token_retention_until < now());
  delete from workflow.workflow_run_keys where run_id = any (v_ids);
  delete from workflow.workflow_runs where id = any (v_ids);
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.workflow_run_get (
  run text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'id', x."id",
    'engine', x."engine",
    'externalId', x."external_id",
    'definition', x."definition",
    'tenant', x."tenant_id",
    'actor', x."actor_id",
    'status', x."status",
    'attributes', x."attributes",
    'error', x."error",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at",
    'startedAt', x."started_at",
    'completedAt', x."completed_at",
    'cancelRequestedAt', x."cancel_requested_at",
    'subjectType', x."subject_type",
    'subjectId', x."subject_id",
    'principalKind', x."principal_kind",
    'principalId', x."principal_id",
    'mode', x."mode",
    'triggerNode', x."trigger_node",
    'idempotencyKey', x."idempotency_key"
  )
  from "better_supabase"."workflow_runs" x
  where x."id"::text = workflow_run_get.run or x."external_id" = workflow_run_get.run
  order by x."id"::text = workflow_run_get.run desc
  limit 1;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.workflow_runs_list (
  tenant       uuid                     DEFAULT NULL::uuid,
  definition   text                     DEFAULT NULL::text,
  status       text                     DEFAULT NULL::text,
  max          integer                  DEFAULT 50,
  before       timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  subject_type text                     DEFAULT NULL::text,
  subject_id   text                     DEFAULT NULL::text,
  mode         text                     DEFAULT 'live'::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', x."id",
    'engine', x."engine",
    'externalId', x."external_id",
    'definition', x."definition",
    'tenant', x."tenant_id",
    'actor', x."actor_id",
    'status', x."status",
    'attributes', x."attributes",
    'error', x."error",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at",
    'startedAt', x."started_at",
    'completedAt', x."completed_at",
    'cancelRequestedAt', x."cancel_requested_at",
    'subjectType', x."subject_type",
    'subjectId', x."subject_id",
    'principalKind', x."principal_kind",
    'principalId', x."principal_id",
    'mode', x."mode",
    'triggerNode', x."trigger_node",
    'idempotencyKey', x."idempotency_key"
  ) order by x."created_at" desc), '[]'::jsonb)
  from (
    select * from "better_supabase"."workflow_runs" y
    where (workflow_runs_list.tenant is null or y."tenant_id" = workflow_runs_list.tenant)
      and (workflow_runs_list.definition is null or y."definition" = workflow_runs_list.definition)
      and (workflow_runs_list.status is null or y."status" = workflow_runs_list.status)
      and (workflow_runs_list.before is null or y."created_at" < workflow_runs_list.before)
      and (workflow_runs_list.subject_type is null or y."subject_type" = workflow_runs_list.subject_type)
      and (workflow_runs_list.subject_id is null or y."subject_id" = workflow_runs_list.subject_id)
      and (workflow_runs_list.mode is null or y."mode" = workflow_runs_list.mode)
    order by y."created_at" desc
    limit least(greatest(coalesce(workflow_runs_list.max, 50), 1), 500)
  ) x;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.workflow_sdk_mirror_run()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_actor uuid;
  v_subject text;
  v_subject_type text;
  v_subject_id text;
  v_principal_kind text;
  v_mode text;
begin
  begin
    v_tenant := (new.attributes ->> 'bsb.tenant')::uuid;
  exception when others then
    v_tenant := null;
  end;
  begin
    v_actor := (new.attributes ->> 'bsb.actor')::uuid;
  exception when others then
    v_actor := null;
  end;
  v_principal_kind := new.attributes ->> 'bsb.principal_kind';
  if v_principal_kind is not null and v_principal_kind not in ('user', 'service_principal', 'system', 'external') then
    v_principal_kind := null;
  end if;
  if v_tenant is not null and v_actor is not null and v_principal_kind is null
    and not coalesce(better_supabase.can_user(v_actor, 'tenant', v_tenant, 'workflows.run'), false) then
    v_tenant := null;
  end if;
  v_subject := new.attributes ->> 'bsb.subject';
  if v_subject is not null and position('/' in v_subject) between 2 and 101
    and length(v_subject) - position('/' in v_subject) between 1 and 200 then
    v_subject_type := left(v_subject, position('/' in v_subject) - 1);
    v_subject_id := substr(v_subject, position('/' in v_subject) + 1);
  end if;
  v_mode := case when new.attributes ->> 'bsb.mode' = 'test' then 'test' else 'live' end;
  perform "better_supabase"."record_workflow_run"(
    'workflow-sdk',
    new.id,
    new.name,
    case new.status::text when 'pending' then 'queued' else new.status::text end,
    v_tenant,
    v_actor,
    coalesce(new.attributes, '{}'::jsonb) - 'bsb.tenant' - 'bsb.actor' - 'bsb.subject' - 'bsb.principal_kind' - 'bsb.principal' - 'bsb.mode' - 'bsb.trigger_node',
    case when new.status::text = 'failed' then coalesce(new.error_code, left(new.error, 4000)) end,
    new.started_at,
    new.completed_at,
    v_subject_type,
    v_subject_id,
    v_principal_kind,
    case when v_principal_kind is null then null else nullif(left(new.attributes ->> 'bsb.principal', 200), '') end,
    v_mode,
    nullif(left(new.attributes ->> 'bsb.trigger_node', 100), '')
  );
  return null;
end;
$function$;

ALTER TABLE "better_supabase"."ai_chat_links"
  ADD CONSTRAINT "ai_chat_links_chat_id_fkey" FOREIGN KEY (chat_id) REFERENCES better_supabase.ai_chats(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."ai_chat_links"
  ADD CONSTRAINT "ai_chat_links_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."ai_chat_participants"
  ADD CONSTRAINT "ai_chat_participants_check" CHECK ((((kind = 'user'::text) AND (user_id IS NOT NULL)) OR ((kind = 'team'::text) AND (team_id IS
    NOT NULL)) OR ((kind = 'customer'::text) AND (customer_user_id IS NOT NULL)) OR ((kind = 'external'::text) AND (email IS NOT NULL))));

ALTER TABLE "better_supabase"."workflow_runs"
  ADD CONSTRAINT "workflow_runs_idempotency_key_check" CHECK (((length(idempotency_key) >= 1) AND (length(idempotency_key) <= 500)));

CREATE INDEX ai_chat_links_created_by_idx ON better_supabase.ai_chat_links USING btree (created_by);

CREATE UNIQUE INDEX ai_chat_participants_customer_key ON better_supabase.ai_chat_participants USING btree (chat_id, customer_user_id)
  WHERE (kind = 'customer'::text);

CREATE UNIQUE INDEX ai_chat_participants_email_key ON better_supabase.ai_chat_participants USING btree (chat_id, lower(email))
  WHERE (kind = 'external'::text);

CREATE UNIQUE INDEX ai_chat_participants_team_key ON better_supabase.ai_chat_participants USING btree (chat_id, team_id)
  WHERE (kind = 'team'::text);

CREATE UNIQUE INDEX ai_chat_participants_user_key ON better_supabase.ai_chat_participants USING btree (chat_id, user_id)
  WHERE (kind = 'user'::text);

CREATE UNIQUE INDEX workflow_runs_idempotency_key ON better_supabase.workflow_runs USING btree (tenant_id, idempotency_key) NULLS NOT DISTINCT
  WHERE (idempotency_key IS NOT NULL);

CREATE UNIQUE INDEX workflow_hooks_token_claim_unique ON workflow.workflow_hooks USING btree (token)
  WHERE claims_token;

CREATE INDEX workflow_start_hook_admissions_created_at_index ON workflow.workflow_start_hook_admissions USING btree (created_at);

CREATE POLICY "ai_chats_read" ON "better_supabase"."ai_chats"
  FOR SELECT
  TO "authenticated"
  USING
    (((owner_id = ( SELECT auth.uid() AS uid)) OR ((visibility = 'organization'::text) AND (organization_id IN ( SELECT better_supabase.tenant_ids_with('ai_chat.read'::text) AS
    tenant_ids_with))) OR ((visibility <> 'private'::text) AND (EXISTS ( SELECT 1
   FROM better_supabase.ai_chat_participants pa
  WHERE ((pa.chat_id = ai_chats.id) AND (((pa.kind = 'user'::text) AND (pa.user_id = ( SELECT auth.uid() AS uid))) OR ((pa.kind = 'team'::text) AND (EXISTS ( SELECT 1
           FROM better_supabase.team_members tm
          WHERE (((tm.team_id)::text = (pa.team_id)::text) AND (tm.user_id = ( SELECT auth.uid() AS uid)))))) OR
            ((pa.kind = 'customer'::text) AND (pa.customer_user_id = ( SELECT auth.uid() AS uid)) AND (((ai_chats.organization_id)::text, 'ai-chat'::text, (ai_chats.id)::text) IN (
            SELECT g.tenant,
            g.subject_type,
            g.subject_id
           FROM better_supabase.portal_subjects('read'::text) g(tenant, subject_type, subject_id)))))))))));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."ai_chats"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((organization_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((owner_id = ( SELECT auth.uid() AS uid)) OR ((visibility =
    'organization'::text) AND (organization_id IN ( SELECT better_supabase.tenant_ids_with('ai_chat.read'::text) AS tenant_ids_with))) OR
    ((visibility <> 'private'::text) AND (EXISTS ( SELECT 1
   FROM better_supabase.ai_chat_participants pa
  WHERE ((pa.chat_id = ai_chats.id) AND (((pa.kind = 'user'::text) AND (pa.user_id = ( SELECT auth.uid() AS uid))) OR ((pa.kind = 'team'::text) AND (EXISTS ( SELECT 1
           FROM better_supabase.team_members tm
          WHERE (((tm.team_id)::text = (pa.team_id)::text) AND (tm.user_id = ( SELECT auth.uid() AS uid)))))) OR
            ((pa.kind = 'customer'::text) AND (pa.customer_user_id = ( SELECT auth.uid() AS uid)) AND (((ai_chats.organization_id)::text, 'ai-chat'::text, (ai_chats.id)::text) IN (
            SELECT g.tenant,
            g.subject_type,
            g.subject_id
           FROM better_supabase.portal_subjects('read'::text) g(tenant, subject_type, subject_id))))))))))));

REVOKE ALL ON FUNCTION "api"."add_ai_chat_party"(uuid, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."add_ai_chat_party"(uuid, text, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."ai_chat_share_summaries"(uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."ai_chat_share_summaries"(uuid[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."claim_workflow_run_dispatch"(uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."claim_workflow_run_dispatch"(uuid, integer) TO "service_role";

REVOKE ALL ON FUNCTION "api"."create_ai_chat_link"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."create_ai_chat_link"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_ai_chat_by_link"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_ai_chat_by_link"(text) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."knowledge_search"(uuid, extensions.vector, text, jsonb, integer, jsonb, uuid[], boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."knowledge_search"(uuid, extensions.vector, text, jsonb, integer, jsonb, uuid[], boolean) TO "authenticated", "service_role";

REVOKE ALL
  ON FUNCTION "api"."record_workflow_run"(text, text, text, text, uuid, uuid, jsonb, text, timestamp WITH time zone, timestamp
    WITH time zone, text, text, text, text, text, text, text)
  FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION "api"."record_workflow_run"(text, text, text, text, uuid, uuid, jsonb, text, timestamp WITH time zone, timestamp
    WITH time zone, text, text, text, text, text, text, text)
  TO "service_role";

REVOKE ALL ON FUNCTION "api"."remove_ai_chat_party"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."remove_ai_chat_party"(uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."revoke_ai_chat_link"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."revoke_ai_chat_link"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."rotate_ai_chat_link"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."rotate_ai_chat_link"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."set_workflow_run_engine"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_workflow_run_engine"(uuid, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."stream_append"(text, integer, bytea[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."stream_append"(text, integer, bytea[]) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."add_ai_chat_party"(uuid, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."add_ai_chat_party"(uuid, text, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."ai_chat_share_summaries"(uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."ai_chat_share_summaries"(uuid[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."chat_state_acquire_lock"(text, text, text, bigint) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."chat_state_acquire_lock"(text, text, text, bigint) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."chat_state_append_to_list"(text, text, jsonb, integer, bigint) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."chat_state_append_to_list"(text, text, jsonb, integer, bigint) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."chat_state_delete"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."chat_state_delete"(text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."chat_state_extend_lock"(text, text, text, bigint) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."chat_state_extend_lock"(text, text, text, bigint) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."chat_state_set"(text, text, jsonb, bigint) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."chat_state_set"(text, text, jsonb, bigint) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."chat_state_set_if_not_exists"(text, text, jsonb, bigint) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."chat_state_set_if_not_exists"(text, text, jsonb, bigint) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."claim_workflow_run_dispatch"(uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."claim_workflow_run_dispatch"(uuid, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."create_ai_chat_link"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."create_ai_chat_link"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_ai_chat_by_link"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_ai_chat_by_link"(text) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."knowledge_search"(uuid, extensions.vector, text, jsonb, integer, jsonb, uuid[], boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."knowledge_search"(uuid, extensions.vector, text, jsonb, integer, jsonb, uuid[], boolean) TO "authenticated", "service_role";

REVOKE ALL
  ON FUNCTION "better_supabase"."record_workflow_run"(text, text, text, text, uuid, uuid, jsonb, text, timestamp WITH time zone, timestamp
    WITH time zone, text, text, text, text, text, text, text)
  FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION "better_supabase"."record_workflow_run"(text, text, text, text, uuid, uuid, jsonb, text, timestamp WITH time zone, timestamp
    WITH time zone, text, text, text, text, text, text, text)
  TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."remove_ai_chat_party"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."remove_ai_chat_party"(uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."revoke_ai_chat_link"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."revoke_ai_chat_link"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."rotate_ai_chat_link"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."rotate_ai_chat_link"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_workflow_run_engine"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_workflow_run_engine"(uuid, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."stream_append"(text, integer, bytea[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."stream_append"(text, integer, bytea[]) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."workflow_open_hooks"(text, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."workflow_open_hooks"(text, text, integer) TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."ai_chat_links" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "workflow"."workflow_start_hook_admissions" TO "service_role";
