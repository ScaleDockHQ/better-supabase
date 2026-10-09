SET local check_function_bodies = off;

DROP FUNCTION "api"."claim_ai_chat_stream"(uuid, text, text, text, text);

DROP FUNCTION "better_supabase"."claim_ai_chat_stream"(uuid, text, text, text, text);

CREATE TABLE "better_supabase"."ai_harness_sessions" (
  "chat_id"        uuid                     NOT NULL,
  "harness_id"     text                     NOT NULL,
  "owner_id"       uuid                     NOT NULL,
  "resume_state"   jsonb,
  "continue_state" jsonb,
  "sandbox_id"     text,
  "status"         text                     NOT NULL DEFAULT 'active'::text,
  "lock_holder"    text,
  "locked_until"   timestamp with time zone,
  "last_active_at" timestamp with time zone NOT NULL DEFAULT now(),
  "created_at"     timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"     timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "ai_harness_sessions_harness_id_check" CHECK (((length(harness_id) >= 1) AND (length(harness_id) <= 200))),
  CONSTRAINT "ai_harness_sessions_lock_holder_check" CHECK ((length(lock_holder) <= 200)),
  CONSTRAINT "ai_harness_sessions_pkey" PRIMARY KEY (chat_id, harness_id),
  CONSTRAINT "ai_harness_sessions_sandbox_id_check" CHECK ((length(sandbox_id) <= 500)),
  CONSTRAINT "ai_harness_sessions_status_check" CHECK ((status = ANY (ARRAY['active'::text, 'idle'::text, 'stopped'::text, 'error'::text])))
);

ALTER TABLE "better_supabase"."ai_harness_sessions"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."ai_run_steps" (
  "id"         uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "run_id"     uuid                     NOT NULL,
  "chat_id"    uuid                     NOT NULL,
  "owner_id"   uuid                     NOT NULL,
  "step_key"   text                     NOT NULL,
  "label"      text                     NOT NULL,
  "status"     text                     NOT NULL DEFAULT 'running'::text,
  "detail"     jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  "started_at" timestamp with time zone NOT NULL DEFAULT now(),
  "ended_at"   timestamp with time zone,
  CONSTRAINT "ai_run_steps_detail_check" CHECK ((jsonb_typeof(detail) = 'object'::text)),
  CONSTRAINT "ai_run_steps_label_check" CHECK (((length(label) >= 1) AND (length(label) <= 300))),
  CONSTRAINT "ai_run_steps_pkey" PRIMARY KEY (id),
  CONSTRAINT "ai_run_steps_run_id_step_key_key" UNIQUE (run_id, step_key),
  CONSTRAINT "ai_run_steps_status_check" CHECK ((status = ANY (ARRAY['running'::text, 'done'::text, 'error'::text, 'skipped'::text]))),
  CONSTRAINT "ai_run_steps_step_key_check" CHECK (((length(step_key) >= 1) AND (length(step_key) <= 200)))
);

ALTER TABLE "better_supabase"."ai_run_steps"
  ENABLE ROW LEVEL SECURITY;

ALTER TABLE "better_supabase"."ai_runs"
  ADD COLUMN "external_run_id" text;

CREATE OR REPLACE FUNCTION api.attach_ai_run (
  run             uuid,
  external_run_id text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."attach_ai_run"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.claim_ai_chat_stream (
  chat            uuid,
  stream          text,
  model           text DEFAULT NULL::text,
  message_id      text DEFAULT NULL::text,
  engine          text DEFAULT 'ai-sdk'::text,
  external_run_id text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."claim_ai_chat_stream"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION api.get_ai_run (
  run uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_ai_run"($1) $function$;

CREATE OR REPLACE FUNCTION api.idle_ai_harness_sessions (
  idle_seconds integer DEFAULT 900,
  size         integer DEFAULT 100
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."idle_ai_harness_sessions"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_ai_run_steps (
  run uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_ai_run_steps"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_ai_runs (
  chat   uuid    DEFAULT NULL::uuid,
  active boolean DEFAULT NULL::boolean,
  size   integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_ai_runs"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.list_pending_ai_tool_approvals (
  size integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_pending_ai_tool_approvals"($1) $function$;

CREATE OR REPLACE FUNCTION api.load_ai_harness_session (
  chat    uuid,
  harness text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."load_ai_harness_session"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.lock_ai_harness_session (
  chat        uuid,
  harness     text,
  holder      text,
  ttl_seconds integer DEFAULT 300
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."lock_ai_harness_session"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.record_ai_run_step (
  run  uuid,
  step jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."record_ai_run_step"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.save_ai_harness_session (
  chat    uuid,
  harness text,
  fields  jsonb,
  holder  text  DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_ai_harness_session"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.unlock_ai_harness_session (
  chat    uuid,
  harness text,
  holder  text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."unlock_ai_harness_session"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION better_supabase.attach_ai_run (
  run             uuid,
  external_run_id text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_count integer;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the server records this' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  update "better_supabase"."ai_runs" x set "external_run_id" = attach_ai_run.external_run_id
  where x."id" = attach_ai_run.run;
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.claim_ai_chat_stream (
  chat            uuid,
  stream          text,
  model           text DEFAULT NULL::text,
  message_id      text DEFAULT NULL::text,
  engine          text DEFAULT 'ai-sdk'::text,
  external_run_id text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_chat "better_supabase"."ai_chats";
  v_run "better_supabase"."ai_runs";
  v_run_id uuid;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the server saves replies' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  select * into v_chat from "better_supabase"."ai_chats" x where x."id" = claim_ai_chat_stream.chat for update;
  if not found then
    raise exception 'No chat %', claim_ai_chat_stream.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  if v_chat."active_stream_id" is not null then
    select * into v_run from "better_supabase"."ai_runs" x where x."id" = v_chat."active_run_id";
    if v_chat."active_stream_id" = claim_ai_chat_stream.stream then
      return jsonb_build_object('claimed', true, 'stream_id', v_chat."active_stream_id", 'run_id', v_chat."active_run_id");
    end if;
    if v_run."id" is not null
      and v_run."status" in ('queued', 'running', 'cancel_requested')
      and v_run."started_at" > now() - interval '10 minutes'
      and not exists (
        select 1 from "better_supabase"."streams" so
        where so."id" = v_chat."active_stream_id" and so."closed_at" is not null
      ) then
      return jsonb_build_object('claimed', false, 'stream_id', v_chat."active_stream_id", 'run_id', v_chat."active_run_id");
    end if;
    update "better_supabase"."ai_runs" x set "status" = 'stopped', "ended_at" = now()
    where x."id" = v_chat."active_run_id" and x."ended_at" is null;
  end if;
  insert into "better_supabase"."ai_runs" ("chat_id", "owner_id", "assistant_message_id", "stream_id", "engine", "external_run_id", "model")
  values (v_chat."id", v_chat."owner_id", claim_ai_chat_stream.message_id, claim_ai_chat_stream.stream, coalesce(claim_ai_chat_stream.engine, 'ai-sdk'), claim_ai_chat_stream.external_run_id, coalesce(claim_ai_chat_stream.model, v_chat."model"))
  returning "id" into v_run_id;
  update "better_supabase"."ai_chats" x set "active_stream_id" = claim_ai_chat_stream.stream, "active_run_id" = v_run_id, "updated_at" = now()
  where x."id" = v_chat."id";
  perform "better_supabase"."ai_chat_notify"(v_chat."id", null, 'stream.started', jsonb_build_object('streamId', claim_ai_chat_stream.stream, 'runId', v_run_id), false);
  return jsonb_build_object('claimed', true, 'stream_id', claim_ai_chat_stream.stream, 'run_id', v_run_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_ai_run (
  run uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_run "better_supabase"."ai_runs";
begin
  select * into v_run from "better_supabase"."ai_runs" x where x."id" = get_ai_run.run;
  if not found or not "better_supabase"."ai_chat_can_read"(v_run."chat_id") then
    raise exception 'No run %', get_ai_run.run using errcode = 'P0002', hint = 'AI_RUN_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_run."id", 'chat_id', v_run."chat_id", 'owner_id', v_run."owner_id", 'assistant_message_id', v_run."assistant_message_id", 'stream_id', v_run."stream_id", 'engine', v_run."engine", 'external_run_id', v_run."external_run_id", 'model', v_run."model", 'status', v_run."status", 'usage', v_run."usage", 'cost_micro_usd', v_run."cost_micro_usd", 'error', v_run."error", 'started_at', v_run."started_at", 'ended_at', v_run."ended_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.idle_ai_harness_sessions (
  idle_seconds integer DEFAULT 900,
  size         integer DEFAULT 100
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_result jsonb;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the server records this' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  with picked as (
    select x."chat_id", x."harness_id" from "better_supabase"."ai_harness_sessions" x
    where x."status" = 'active' and x."sandbox_id" is not null
      and x."last_active_at" < now() - make_interval(secs => greatest(coalesce(idle_ai_harness_sessions.idle_seconds, 900), 1))
      and (x."locked_until" is null or x."locked_until" <= now())
    order by x."last_active_at"
    limit least(greatest(coalesce(idle_ai_harness_sessions.size, 100), 1), 1000)
    for update skip locked
  ), marked as (
    update "better_supabase"."ai_harness_sessions" x set "status" = 'idle', "updated_at" = now()
    from picked
    where x."chat_id" = picked."chat_id" and x."harness_id" = picked."harness_id"
    returning x.*
  )
  select coalesce(jsonb_agg(jsonb_build_object('chat_id', marked."chat_id", 'harness_id', marked."harness_id", 'owner_id', marked."owner_id", 'resume_state', marked."resume_state", 'continue_state', marked."continue_state", 'sandbox_id', marked."sandbox_id", 'status', marked."status", 'lock_holder', marked."lock_holder", 'locked_until', marked."locked_until", 'last_active_at', marked."last_active_at", 'created_at', marked."created_at", 'updated_at', marked."updated_at")), '[]'::jsonb) into v_result from marked;
  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_ai_run_steps (
  run uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_run "better_supabase"."ai_runs";
begin
  select * into v_run from "better_supabase"."ai_runs" x where x."id" = list_ai_run_steps.run;
  if not found or not "better_supabase"."ai_chat_can_read"(v_run."chat_id") then
    raise exception 'No run %', list_ai_run_steps.run using errcode = 'P0002', hint = 'AI_RUN_NOT_FOUND';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'run_id', x."run_id", 'chat_id', x."chat_id", 'step_key', x."step_key", 'label', x."label", 'status', x."status", 'detail', x."detail", 'started_at', x."started_at", 'ended_at', x."ended_at") order by x."started_at", x."id"), '[]'::jsonb)
    from "better_supabase"."ai_run_steps" x where x."run_id" = v_run."id"
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_ai_runs (
  chat   uuid    DEFAULT NULL::uuid,
  active boolean DEFAULT NULL::boolean,
  size   integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if list_ai_runs.chat is not null and not "better_supabase"."ai_chat_can_read"(list_ai_runs.chat) then
    raise exception 'No chat %', list_ai_runs.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'chat_id', y."chat_id", 'owner_id', y."owner_id", 'assistant_message_id', y."assistant_message_id", 'stream_id', y."stream_id", 'engine', y."engine", 'external_run_id', y."external_run_id", 'model', y."model", 'status', y."status", 'usage', y."usage", 'cost_micro_usd', y."cost_micro_usd", 'error', y."error", 'started_at', y."started_at", 'ended_at', y."ended_at") order by y."started_at" desc), '[]'::jsonb)
    from (
      select * from "better_supabase"."ai_runs" x
      where (
          case when list_ai_runs.chat is not null then x."chat_id" = list_ai_runs.chat
          else coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or x."owner_id" = (select auth.uid()) end
        )
        and (
          list_ai_runs.active is null
          or (x."status" in ('queued', 'running', 'cancel_requested')) = list_ai_runs.active
        )
      order by x."started_at" desc
      limit least(greatest(coalesce(list_ai_runs.size, 50), 1), 200)
    ) y
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_pending_ai_tool_approvals (
  size integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(y.approval order by y.created desc), '[]'::jsonb)
  from (
    select jsonb_build_object('approval_id', x."approval_id", 'chat_id', x."chat_id", 'run_id', x."run_id", 'message_id', x."message_id", 'tool', x."tool", 'tool_call_id', x."tool_call_id", 'input', x."input", 'decision', x."decision", 'reason', x."reason", 'signature', x."signature", 'decided_by', x."decided_by", 'decided_at', x."decided_at", 'created_at', x."created_at") || jsonb_build_object('chat_title', c."title") as approval, x."created_at" as created
    from "better_supabase"."ai_tool_approvals" x
    join "better_supabase"."ai_chats" c on c."id" = x."chat_id"
    where x."owner_id" = (select auth.uid()) and x."decision" is null
    order by x."created_at" desc
    limit least(greatest(coalesce(list_pending_ai_tool_approvals.size, 50), 1), 200)
  ) y;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.load_ai_harness_session (
  chat    uuid,
  harness text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."ai_harness_sessions";
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the server records this' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."ai_harness_sessions" x
  where x."chat_id" = load_ai_harness_session.chat and x."harness_id" = load_ai_harness_session.harness;
  if not found then
    return null;
  end if;
  return jsonb_build_object('chat_id', v_row."chat_id", 'harness_id', v_row."harness_id", 'owner_id', v_row."owner_id", 'resume_state', v_row."resume_state", 'continue_state', v_row."continue_state", 'sandbox_id', v_row."sandbox_id", 'status', v_row."status", 'lock_holder', v_row."lock_holder", 'locked_until', v_row."locked_until", 'last_active_at', v_row."last_active_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.lock_ai_harness_session (
  chat        uuid,
  harness     text,
  holder      text,
  ttl_seconds integer DEFAULT 300
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_chat "better_supabase"."ai_chats";
  v_row "better_supabase"."ai_harness_sessions";
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the server records this' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  if nullif(lock_ai_harness_session.harness, '') is null then
    raise exception 'A harness session needs a harness id' using errcode = '22023', hint = 'AI_HARNESS_INVALID';
  end if;
  if nullif(lock_ai_harness_session.holder, '') is null
    or coalesce(lock_ai_harness_session.ttl_seconds, 0) not between 1 and 86400 then
    raise exception 'A lock needs a holder and a ttl between 1 and 86400 seconds' using errcode = '22023', hint = 'AI_HARNESS_INVALID';
  end if;
  select * into v_chat from "better_supabase"."ai_chats" x where x."id" = lock_ai_harness_session.chat;
  if not found then
    raise exception 'No chat %', lock_ai_harness_session.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  insert into "better_supabase"."ai_harness_sessions" ("chat_id", "harness_id", "owner_id")
  values (v_chat."id", lock_ai_harness_session.harness, v_chat."owner_id")
  on conflict ("chat_id", "harness_id") do nothing;
  select * into v_row from "better_supabase"."ai_harness_sessions" x
  where x."chat_id" = v_chat."id" and x."harness_id" = lock_ai_harness_session.harness
  for update;
  if v_row."locked_until" > now() and v_row."lock_holder" is distinct from lock_ai_harness_session.holder then
    return false;
  end if;
  update "better_supabase"."ai_harness_sessions" x set
    "lock_holder" = lock_ai_harness_session.holder,
    "locked_until" = now() + make_interval(secs => lock_ai_harness_session.ttl_seconds),
    "updated_at" = now()
  where x."chat_id" = v_row."chat_id" and x."harness_id" = v_row."harness_id";
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_ai_run_step (
  run  uuid,
  step jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_run "better_supabase"."ai_runs";
  v_row "better_supabase"."ai_run_steps";
  v_status text := coalesce(record_ai_run_step.step ->> 'status', 'running');
  v_detail jsonb := coalesce(record_ai_run_step.step -> 'detail', '{}'::jsonb);
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the server records this' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  select * into v_run from "better_supabase"."ai_runs" x where x."id" = record_ai_run_step.run;
  if not found then
    raise exception 'No run %', record_ai_run_step.run using errcode = 'P0002', hint = 'AI_RUN_NOT_FOUND';
  end if;
  if nullif(record_ai_run_step.step ->> 'key', '') is null
    or v_status not in ('running', 'done', 'error', 'skipped')
    or jsonb_typeof(v_detail) <> 'object' then
    raise exception 'A step needs a key, a status of running, done, error or skipped and an object detail' using errcode = '22023', hint = 'AI_RUN_STEP_INVALID';
  end if;
  insert into "better_supabase"."ai_run_steps" ("run_id", "chat_id", "owner_id", "step_key", "label", "status", "detail", "ended_at")
  values (
    v_run."id", v_run."chat_id", v_run."owner_id", record_ai_run_step.step ->> 'key',
    coalesce(nullif(record_ai_run_step.step ->> 'label', ''), record_ai_run_step.step ->> 'key'),
    v_status, v_detail, case when v_status <> 'running' then now() end
  )
  on conflict ("run_id", "step_key") do update set
    "label" = coalesce(nullif(record_ai_run_step.step ->> 'label', ''), "better_supabase"."ai_run_steps"."label"),
    "status" = excluded."status",
    "detail" = "better_supabase"."ai_run_steps"."detail" || excluded."detail",
    "ended_at" = case when excluded."status" <> 'running' then coalesce("better_supabase"."ai_run_steps"."ended_at", now()) end
  returning * into v_row;
  perform "better_supabase"."ai_chat_notify"(v_run."chat_id", null, 'run.step', jsonb_build_object('runId', v_run."id", 'key', v_row."step_key", 'status', v_row."status"), false);
  return jsonb_build_object('id', v_row."id", 'run_id', v_row."run_id", 'chat_id', v_row."chat_id", 'step_key', v_row."step_key", 'label', v_row."label", 'status', v_row."status", 'detail', v_row."detail", 'started_at', v_row."started_at", 'ended_at', v_row."ended_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_ai_harness_session (
  chat    uuid,
  harness text,
  fields  jsonb,
  holder  text  DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_chat "better_supabase"."ai_chats";
  v_row "better_supabase"."ai_harness_sessions";
  v_status text := save_ai_harness_session.fields ->> 'status';
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the server records this' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  if nullif(save_ai_harness_session.harness, '') is null then
    raise exception 'A harness session needs a harness id' using errcode = '22023', hint = 'AI_HARNESS_INVALID';
  end if;
  if jsonb_typeof(save_ai_harness_session.fields) is distinct from 'object'
    or (v_status is not null and v_status not in ('active', 'idle', 'stopped', 'error')) then
    raise exception 'fields must be an object and status active, idle, stopped or error' using errcode = '22023', hint = 'AI_HARNESS_INVALID';
  end if;
  select * into v_chat from "better_supabase"."ai_chats" x where x."id" = save_ai_harness_session.chat;
  if not found then
    raise exception 'No chat %', save_ai_harness_session.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  insert into "better_supabase"."ai_harness_sessions" ("chat_id", "harness_id", "owner_id")
  values (v_chat."id", save_ai_harness_session.harness, v_chat."owner_id")
  on conflict ("chat_id", "harness_id") do nothing;
  select * into v_row from "better_supabase"."ai_harness_sessions" x
  where x."chat_id" = v_chat."id" and x."harness_id" = save_ai_harness_session.harness
  for update;
  if v_row."locked_until" > now() and v_row."lock_holder" is distinct from save_ai_harness_session.holder then
    raise exception 'Harness session % is locked', save_ai_harness_session.harness using errcode = '55P03', hint = 'AI_HARNESS_LOCKED';
  end if;
  update "better_supabase"."ai_harness_sessions" x set
    "resume_state" = case when save_ai_harness_session.fields ? 'resume_state' then save_ai_harness_session.fields -> 'resume_state' else x."resume_state" end,
    "continue_state" = case when save_ai_harness_session.fields ? 'continue_state' then save_ai_harness_session.fields -> 'continue_state' else x."continue_state" end,
    "sandbox_id" = case when save_ai_harness_session.fields ? 'sandbox_id' then save_ai_harness_session.fields ->> 'sandbox_id' else x."sandbox_id" end,
    "status" = coalesce(v_status, x."status"),
    "last_active_at" = now(),
    "updated_at" = now()
  where x."chat_id" = v_row."chat_id" and x."harness_id" = v_row."harness_id"
  returning * into v_row;
  return jsonb_build_object('chat_id', v_row."chat_id", 'harness_id', v_row."harness_id", 'owner_id', v_row."owner_id", 'resume_state', v_row."resume_state", 'continue_state', v_row."continue_state", 'sandbox_id', v_row."sandbox_id", 'status', v_row."status", 'lock_holder', v_row."lock_holder", 'locked_until', v_row."locked_until", 'last_active_at', v_row."last_active_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.unlock_ai_harness_session (
  chat    uuid,
  harness text,
  holder  text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_count integer;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the server records this' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  update "better_supabase"."ai_harness_sessions" x set "lock_holder" = null, "locked_until" = null, "updated_at" = now()
  where x."chat_id" = unlock_ai_harness_session.chat
    and x."harness_id" = unlock_ai_harness_session.harness
    and x."lock_holder" = unlock_ai_harness_session.holder;
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$function$;

ALTER TABLE "better_supabase"."ai_harness_sessions"
  ADD CONSTRAINT "ai_harness_sessions_chat_id_fkey" FOREIGN KEY (chat_id) REFERENCES better_supabase.ai_chats(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."ai_run_steps"
  ADD CONSTRAINT "ai_run_steps_chat_id_fkey" FOREIGN KEY (chat_id) REFERENCES better_supabase.ai_chats(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."ai_run_steps"
  ADD CONSTRAINT "ai_run_steps_run_id_fkey" FOREIGN KEY (run_id) REFERENCES better_supabase.ai_runs(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."ai_runs"
  ADD CONSTRAINT "ai_runs_external_run_id_check" CHECK ((length(external_run_id) <= 200));

CREATE INDEX ai_harness_sessions_idle_idx ON better_supabase.ai_harness_sessions USING btree (last_active_at)
  WHERE ((status = 'active'::text) AND (sandbox_id IS NOT NULL));

CREATE INDEX ai_harness_sessions_owner_idx ON better_supabase.ai_harness_sessions USING btree (owner_id);

CREATE INDEX ai_run_steps_chat_idx ON better_supabase.ai_run_steps USING btree (chat_id);

CREATE INDEX ai_run_steps_owner_idx ON better_supabase.ai_run_steps USING btree (owner_id);

CREATE INDEX ai_runs_external_idx ON better_supabase.ai_runs USING btree (engine, external_run_id)
  WHERE (external_run_id IS NOT NULL);

CREATE POLICY "ai_harness_sessions_owner_read" ON "better_supabase"."ai_harness_sessions"
  FOR SELECT
  TO "authenticated"
  USING ((owner_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "ai_run_steps_owner_read" ON "better_supabase"."ai_run_steps"
  FOR SELECT
  TO "authenticated"
  USING ((owner_id = ( SELECT auth.uid() AS uid)));

REVOKE ALL ON FUNCTION "api"."attach_ai_run"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."attach_ai_run"(uuid, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."claim_ai_chat_stream"(uuid, text, text, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."claim_ai_chat_stream"(uuid, text, text, text, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."get_ai_run"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_ai_run"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."idle_ai_harness_sessions"(integer, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."idle_ai_harness_sessions"(integer, integer) TO "service_role";

REVOKE ALL ON FUNCTION "api"."list_ai_run_steps"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_ai_run_steps"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_ai_runs"(uuid, boolean, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_ai_runs"(uuid, boolean, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_pending_ai_tool_approvals"(integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_pending_ai_tool_approvals"(integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."load_ai_harness_session"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."load_ai_harness_session"(uuid, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."lock_ai_harness_session"(uuid, text, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."lock_ai_harness_session"(uuid, text, text, integer) TO "service_role";

REVOKE ALL ON FUNCTION "api"."record_ai_run_step"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."record_ai_run_step"(uuid, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "api"."save_ai_harness_session"(uuid, text, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_ai_harness_session"(uuid, text, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."unlock_ai_harness_session"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."unlock_ai_harness_session"(uuid, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."attach_ai_run"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."attach_ai_run"(uuid, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."claim_ai_chat_stream"(uuid, text, text, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."claim_ai_chat_stream"(uuid, text, text, text, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_ai_run"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_ai_run"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."idle_ai_harness_sessions"(integer, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."idle_ai_harness_sessions"(integer, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_ai_run_steps"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_ai_run_steps"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_ai_runs"(uuid, boolean, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_ai_runs"(uuid, boolean, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_pending_ai_tool_approvals"(integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_pending_ai_tool_approvals"(integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."load_ai_harness_session"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."load_ai_harness_session"(uuid, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."lock_ai_harness_session"(uuid, text, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."lock_ai_harness_session"(uuid, text, text, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."record_ai_run_step"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."record_ai_run_step"(uuid, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_ai_harness_session"(uuid, text, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_ai_harness_session"(uuid, text, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."unlock_ai_harness_session"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."unlock_ai_harness_session"(uuid, text, text) TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."ai_harness_sessions" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."ai_harness_sessions" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."ai_run_steps" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."ai_run_steps" TO "service_role";
