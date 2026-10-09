SET local check_function_bodies = off;

DROP FUNCTION "api"."idle_ai_harness_sessions"(integer, integer);

DROP FUNCTION "better_supabase"."idle_ai_harness_sessions"(integer, integer);

CREATE OR REPLACE FUNCTION better_supabase.release_ai_chat_stream (
  chat           uuid,
  stream         text,
  status         text   DEFAULT 'completed'::text,
  usage          jsonb  DEFAULT NULL::jsonb,
  generation_id  text   DEFAULT NULL::text,
  error          text   DEFAULT NULL::text,
  cost_micro_usd bigint DEFAULT NULL::bigint
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_status text := coalesce(release_ai_chat_stream.status, 'completed');
  v_found boolean := false;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the server saves replies' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  if v_status not in ('completed', 'failed', 'cancelled') then
    raise exception 'A run ends completed, failed or cancelled, not %', v_status using errcode = '22023', hint = 'AI_RUN_INVALID';
  end if;
  update "better_supabase"."ai_runs" x set
    "status" = v_status,
    "usage" = coalesce(release_ai_chat_stream.usage, x."usage"),
    "provider_generation_id" = coalesce(release_ai_chat_stream.generation_id, x."provider_generation_id"),
    "error" = release_ai_chat_stream.error,
    "cost_micro_usd" = coalesce(release_ai_chat_stream.cost_micro_usd, x."cost_micro_usd"),
    "ended_at" = coalesce(x."ended_at", now())
  where x."chat_id" = release_ai_chat_stream.chat and x."stream_id" = release_ai_chat_stream.stream;
  update "better_supabase"."ai_chats" x set "active_stream_id" = null, "active_run_id" = null, "updated_at" = now()
  where x."id" = release_ai_chat_stream.chat and x."active_stream_id" = release_ai_chat_stream.stream
  returning true into v_found;
  if coalesce(v_found, false) then
    perform "better_supabase"."ai_chat_notify"(release_ai_chat_stream.chat, null, 'stream.ended', jsonb_build_object('streamId', release_ai_chat_stream.stream, 'status', v_status), false);
  end if;
  return coalesce(v_found, false);
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
    -- A save without a status is a turn using the sandbox: an idle session
    -- turns active again.
    "status" = coalesce(v_status, case when x."status" = 'idle' then 'active' else x."status" end),
    "last_active_at" = now(),
    "updated_at" = now()
  where x."chat_id" = v_row."chat_id" and x."harness_id" = v_row."harness_id"
  returning * into v_row;
  if save_ai_harness_session.fields ? 'sandbox_id' then
    if nullif(save_ai_harness_session.fields ->> 'sandbox_id', '') is null then
      update "better_supabase"."ai_sandboxes" y set "status" = 'stopped', "stopped_at" = now(), "updated_at" = now()
      where y."chat_id" = v_row."chat_id" and y."harness_id" = v_row."harness_id" and y."status" <> 'stopped';
    else
      insert into "better_supabase"."ai_sandboxes" as cur ("organization_id", "user_id", "chat_id", "harness_id", "provider", "sandbox_id")
      values (v_chat."organization_id", v_chat."owner_id", v_chat."id", v_row."harness_id", coalesce(nullif(save_ai_harness_session.fields ->> 'sandbox_provider', ''), 'harness'), save_ai_harness_session.fields ->> 'sandbox_id')
      on conflict ("provider", "sandbox_id") do update set
        "chat_id" = excluded."chat_id",
        "harness_id" = excluded."harness_id",
        "status" = 'running',
        "error" = null,
        "stopped_at" = null,
        "last_used_at" = now(),
        "updated_at" = now()
      where cur."organization_id" = excluded."organization_id";
      if not found then
        raise exception 'sandbox % belongs to another tenant', save_ai_harness_session.fields ->> 'sandbox_id' using errcode = '42501', hint = 'AI_SANDBOX_FORBIDDEN';
      end if;
    end if;
  elsif save_ai_harness_session.fields ->> 'status' is null then
    update "better_supabase"."ai_sandboxes" y set "last_used_at" = now(), "updated_at" = now()
    where y."chat_id" = v_row."chat_id" and y."harness_id" = v_row."harness_id" and y."status" = 'running';
  end if;
  return jsonb_build_object('chat_id', v_row."chat_id", 'harness_id', v_row."harness_id", 'owner_id', v_row."owner_id", 'resume_state', v_row."resume_state", 'continue_state', v_row."continue_state", 'sandbox_id', (select y."sandbox_id" from "better_supabase"."ai_sandboxes" y where y."chat_id" = v_row."chat_id" and y."harness_id" = v_row."harness_id" and y."status" <> 'stopped' order by y."last_used_at" desc limit 1), 'status', v_row."status", 'lock_holder', v_row."lock_holder", 'locked_until', v_row."locked_until", 'last_active_at', v_row."last_active_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;
