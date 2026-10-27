SET local check_function_bodies = off;

DROP FUNCTION "api"."list_inbox_messages"(uuid, timestamp WITH time zone, integer);

CREATE OR REPLACE FUNCTION api.list_inbox_messages (
  conversation uuid,
  before       timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  max          integer                  DEFAULT 50,
  after        timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_inbox_messages"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION better_supabase.list_inbox_messages (
  conversation uuid,
  before       timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  max          integer                  DEFAULT 50,
  after        timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not "better_supabase"."inbox_conversation_allowed"(list_inbox_messages.conversation::text) then
    return '[]'::jsonb;
  end if;
  return "better_supabase"."inbox_messages_json"(array(
    select m."id" from "better_supabase"."messages" m
    where m."conversation_id" = list_inbox_messages.conversation
      and m."sent_at" is not null
      and (list_inbox_messages.before is null or m."sent_at" < list_inbox_messages.before)
      and (list_inbox_messages.after is null or m."sent_at" > list_inbox_messages.after)
      and (m."kind" = 'message' or "better_supabase"."inbox_note_readable"(list_inbox_messages.conversation))
    order by
      case when list_inbox_messages.after is null then m."sent_at" end desc,
      case when list_inbox_messages.after is null then m."id" end desc,
      m."sent_at", m."id"
    limit least(greatest(coalesce(list_inbox_messages.max, 50), 1), 200)
  ));
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
  v_contact := "better_supabase"."inbox_resolve_contact"(v_inbox."tenant_id", v_contact_input);
  v_id := gen_random_uuid();
  insert into "better_supabase"."conversations" ("id", "tenant_id", "kind", "access", "created_by")
  values (v_id, v_inbox."tenant_id", 'inbox', 'tenant', (select auth.uid()));
  insert into "better_supabase"."inbox_conversations" ("id", "tenant_id", "inbox_id", "contact_id", "subject", "priority", "bot_mode", "thread_id", "assignee_id", "metadata")
  values (
    v_id, v_inbox."tenant_id", v_inbox."id", v_contact."id", input ->> 'subject', coalesce(input ->> 'priority', 'normal'),
    coalesce(input ->> 'bot_mode', v_inbox."bot_mode"), coalesce(input ->> 'thread_id', 'inbox:' || v_inbox."id"::text || ':' || v_id::text),
    case when v_staff then (input ->> 'assignee_id')::uuid end, coalesce(input -> 'metadata', '{}'::jsonb)
  )
  returning * into v_conv;
  if v_contact."user_id" is not null then
    insert into "better_supabase"."conversation_members" ("conversation_id", "tenant_id", "user_id")
    values (v_id, v_inbox."tenant_id", v_contact."user_id")
    on conflict do nothing;
  end if;
  if v_conv."assignee_id" is not null then
    insert into "better_supabase"."conversation_members" ("conversation_id", "tenant_id", "user_id")
    values (v_id, v_inbox."tenant_id", v_conv."assignee_id")
    on conflict do nothing;
  end if;
  insert into "better_supabase"."conversation_events" ("tenant_id", "conversation_id", "type", "actor_id", "data")
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

REVOKE ALL ON FUNCTION "api"."list_inbox_messages"(uuid, timestamp WITH time zone, integer, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_inbox_messages"(uuid, timestamp WITH time zone, integer, timestamp WITH time zone) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_inbox_messages"(uuid, timestamp WITH time zone, integer, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_inbox_messages"(uuid, timestamp WITH time zone, integer, timestamp WITH time zone) TO "authenticated", "service_role";
