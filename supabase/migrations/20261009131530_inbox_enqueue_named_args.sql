SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.inbox_add_message (
  conversation uuid,
  input        jsonb,
  author_type  text,
  author       uuid,
  direction    text
)
  RETURNS better_supabase.inbox_messages
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_conv "better_supabase"."conversations"%rowtype;
  v_inbox "better_supabase"."inboxes"%rowtype;
  v_msg "better_supabase"."inbox_messages"%rowtype;
  v_kind text := coalesce(input ->> 'kind', 'message');
  v_mentions uuid[];
  v_reopened boolean := false;
  v_claims text;
begin
  select * into v_conv from "better_supabase"."conversations" where "id" = inbox_add_message.conversation for update;
  select * into v_inbox from "better_supabase"."inboxes" where "id" = v_conv."inbox_id";
  if input ? 'external_id' then
    select * into v_msg from "better_supabase"."inbox_messages" m
    where m."conversation_id" = v_conv."id" and m."external_id" = input ->> 'external_id';
    if found then
      return v_msg;
    end if;
  end if;
  if length(btrim(coalesce(input ->> 'body', ''))) = 0 and coalesce(jsonb_array_length(input -> 'attachments'), 0) = 0 then
    raise exception 'a message needs a body or an attachment' using errcode = '22023', hint = 'INBOX_MESSAGE_EMPTY';
  end if;
  select coalesce(array_agg(distinct x), '{}') into v_mentions
  from jsonb_array_elements_text(coalesce(input -> 'mentions', '[]'::jsonb)) e(raw)
  cross join lateral (select e.raw::uuid as x) u
  where coalesce(better_supabase.can_user(u.x, 'tenant', v_conv."tenant_id", 'inbox.read'), false);
  insert into "better_supabase"."inbox_messages" ("tenant_id", "conversation_id", "direction", "kind", "author_type", "author_id", "body", "format", "attachments", "mentions", "external_id", "reply_to", "metadata")
  values (
    v_conv."tenant_id", v_conv."id", inbox_add_message.direction, v_kind, inbox_add_message.author_type, inbox_add_message.author,
    coalesce(input ->> 'body', ''), coalesce(input ->> 'format', 'text'), coalesce(input -> 'attachments', '[]'::jsonb), v_mentions,
    input ->> 'external_id', (input ->> 'reply_to')::uuid, coalesce(input -> 'metadata', '{}'::jsonb)
  )
  returning * into v_msg;
  insert into "better_supabase"."inbox_mentions" ("message_id", "user_id", "tenant_id")
  select v_msg."id", x, v_msg."tenant_id" from unnest(v_mentions) x
  on conflict do nothing;
  if v_kind = 'message' then
    v_reopened := inbox_add_message.direction = 'inbound' and v_conv."status" in ('resolved', 'snoozed');
    update "better_supabase"."conversations" set
      "last_message_at" = v_msg."created_at",
      "last_message_preview" = left(v_msg."body", 140),
      "first_response_at" = case
        when "first_response_at" is null and inbox_add_message.direction = 'outbound' and inbox_add_message.author_type in ('agent', 'bot') then v_msg."created_at"
        else "first_response_at" end,
      "status" = case when v_reopened then 'open' else "status" end,
      "snoozed_until" = case when v_reopened then null else "snoozed_until" end,
      "resolved_at" = case when v_reopened then null else "resolved_at" end
    where "id" = v_conv."id"
    returning * into v_conv;
    if v_reopened then
      insert into "better_supabase"."conversation_events" ("tenant_id", "conversation_id", "type", "actor_id", "data")
  values (v_conv."tenant_id", v_conv."id", 'reopened', (select auth.uid()), jsonb_build_object('by', 'contact'));
      
    end if;
  end if;
  if inbox_add_message.author is not null and inbox_add_message.author_type = 'agent' then
    insert into "better_supabase"."conversation_participants" ("conversation_id", "user_id") values (v_conv."id", inbox_add_message.author)
    on conflict do nothing;
  end if;
  if v_kind = 'message' and inbox_add_message.direction = 'inbound' then
    
    if v_conv."bot_mode" = 'bot' then
      perform "better_supabase"."enqueue_job"(queue => 'inbox_bot', payload => jsonb_build_object('conversation_id', v_conv."id", 'message_id', v_msg."id", 'thread_id', v_conv."thread_id", 'inbox_id', v_conv."inbox_id"), dedupe_key => 'inbox:' || v_conv."id"::text, dedupe_running => false);
    end if;
  v_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
  perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'inbox.message',
      'tenant', v_conv."tenant_id",
      'subject_type', 'conversation',
      'subject_id', v_conv."id"::text,
      'summary', left(v_msg."body", 140),
      'recipients', case when v_conv."assignee_id" is not null then to_jsonb(array[v_conv."assignee_id"])
    else coalesce((select jsonb_agg(m."user_id") from "better_supabase"."inbox_members" m where m."inbox_id" = v_conv."inbox_id"), '[]'::jsonb) end,
      'key', 'inbox.message:' || v_msg."id"::text,
      'data', jsonb_build_object('conversationId', v_conv."id", 'messageId', v_msg."id")
    ));
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  if v_kind = 'message' and inbox_add_message.direction = 'outbound' and v_inbox."channel" <> 'in_app' then
    insert into "better_supabase"."message_deliveries" ("tenant_id", "message_id", "channel")
    values (v_msg."tenant_id", v_msg."id", v_inbox."channel")
    on conflict do nothing;
    if not coalesce((input ->> 'delivered_by_caller')::boolean, false) then
      perform "better_supabase"."enqueue_job"(queue => 'inbox_outbound', payload => jsonb_build_object('message_id', v_msg."id", 'conversation_id', v_conv."id", 'inbox_id', v_conv."inbox_id"), dedupe_key => 'inbox-out:' || v_msg."id"::text, dedupe_running => false);
    end if;
  end if;
  if cardinality(v_mentions) > 0 then
  v_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
  perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'inbox.mention',
      'tenant', v_conv."tenant_id",
      'actor', inbox_add_message.author,
      'subject_type', 'conversation',
      'subject_id', v_conv."id"::text,
      'summary', left(v_msg."body", 140),
      'recipients', to_jsonb(v_mentions),
      'key', 'inbox.mention:' || v_msg."id"::text,
      'data', jsonb_build_object('conversationId', v_conv."id", 'messageId', v_msg."id")
    ));
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  return v_msg;
end;
$function$;
