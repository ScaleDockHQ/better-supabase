SET local check_function_bodies = off;

ALTER TABLE "better_supabase"."messages"
  ADD COLUMN "author_kind" text;

ALTER TABLE "better_supabase"."messages"
  ADD COLUMN "author_name" text;

CREATE OR REPLACE FUNCTION better_supabase.delete_message (
  message uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_msg "better_supabase"."messages";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_msg from "better_supabase"."messages" m
  where m."id" = delete_message.message and m."archived_at" is null
    and "better_supabase"."can_conversation"(m."conversation_id", 'read');
  if not found then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_msg."author_id" = auth.uid(), false) or "better_supabase"."can_conversation"(v_msg."conversation_id", 'moderate')) then
    raise exception 'not allowed to delete this message' using errcode = '42501', hint = 'MESSAGING_FORBIDDEN';
  end if;
  update "better_supabase"."messages" m set "body" = '', "document" = null, "mentions" = '{}', "mention_scope" = null,
    "pinned_at" = null, "pinned_by" = null, "archived_at" = now()
  where m."id" = v_msg."id"
  returning * into v_msg;
  delete from "better_supabase"."message_edits" x where x."message_id" = v_msg."id";
  delete from "better_supabase"."message_record_mentions" x where x."message_id" = v_msg."id";
  delete from "better_supabase"."attachments" a
  where a."subject_type" = 'message' and a."subject_id" = v_msg."id"::text;
  if v_msg."sent_at" is not null then
    perform "better_supabase".emit_event('message.deleted', jsonb_build_object('organizationId', v_msg."tenant_id"::text, 'conversationId', v_msg."conversation_id", 'messageId', v_msg."id", 'authorId', v_msg."author_id", 'actorKind', v_msg."author_kind", 'actorName', v_msg."author_name", 'threadId', v_msg."thread_id", 'subjectType', 'message', 'subjectId', v_msg."id"::text)
      || coalesce((select jsonb_build_object('conversationKind', c."kind", 'recordType', c."subject_type", 'recordId', c."subject_id") from "better_supabase"."conversations" c where c."id" = v_msg."conversation_id"), '{}'::jsonb), 'messages/' || v_msg."id"::text, (v_msg."tenant_id"::text)::text, null, 'better-supabase/messaging');
  end if;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.edit_message (
  message uuid,
  body    text,
  attrs   jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_msg "better_supabase"."messages";
  v_parsed jsonb := "better_supabase"."parse_mentions"(edit_message.body);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_msg from "better_supabase"."messages" m
  where m."id" = edit_message.message and m."author_id" = auth.uid() and m."archived_at" is null
    and "better_supabase"."can_conversation"(m."conversation_id", 'read');
  if not found then
    raise exception 'no message of yours has this id' using errcode = 'P0002', hint = 'MESSAGING_NOT_FOUND';
  end if;
  if exists (
    select 1 from "better_supabase"."conversations" c
    where c."id" = v_msg."conversation_id"
      and c."access" = 'subject' and c."subject_type" in ('drive_node')
  ) and not "better_supabase"."can_conversation"(v_msg."conversation_id", 'send') then
    raise exception 'not allowed to comment on this record' using errcode = '42501', hint = 'MESSAGING_FORBIDDEN';
  end if;
  if v_msg."sent_at" is not null and not (true) then
    raise exception 'this message can no longer be edited' using errcode = '55000', hint = 'MESSAGING_EDIT_CLOSED';
  end if;
  if nullif(trim(coalesce(edit_message.body, '')), '') is null then
    raise exception 'a message needs a body' using errcode = '23502', hint = 'MESSAGING_BODY_REQUIRED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_message_edit"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using edit_message.message, edit_message.body;
    end if;
  end;
  insert into "better_supabase"."message_edits" ("tenant_id", "message_id", "body", "document", "edited_by")
  values (v_msg."tenant_id", v_msg."id", v_msg."body", v_msg."document", auth.uid());
  begin
    update "better_supabase"."messages" m set
      "body" = edit_message.body,
      "document" = case when edit_message.attrs ? 'document' then edit_message.attrs -> 'document' else m."document" end,
      "mentions" = array(
        select distinct x from (
          select (jsonb_array_elements_text(coalesce(edit_message.attrs -> 'mentions', '[]'::jsonb)))::uuid as x
          union
          select (jsonb_array_elements_text(v_parsed -> 'users'))::uuid
        ) s
      ),
      "edited_at" = now()
    where m."id" = v_msg."id"
    returning * into v_msg;
  exception when check_violation or invalid_text_representation then
    raise exception 'a message field has an invalid value' using errcode = '22023', hint = 'MESSAGING_MESSAGE_INVALID';
  end;
  if v_msg."sent_at" is not null then
    perform "better_supabase"."index_record_mentions"(v_msg."id");
    perform "better_supabase".emit_event('message.updated', jsonb_build_object('organizationId', v_msg."tenant_id"::text, 'conversationId', v_msg."conversation_id", 'messageId', v_msg."id", 'authorId', v_msg."author_id", 'actorKind', v_msg."author_kind", 'actorName', v_msg."author_name", 'threadId', v_msg."thread_id", 'subjectType', 'message', 'subjectId', v_msg."id"::text)
      || coalesce((select jsonb_build_object('conversationKind', c."kind", 'recordType', c."subject_type", 'recordId', c."subject_id") from "better_supabase"."conversations" c where c."id" = v_msg."conversation_id"), '{}'::jsonb), 'messages/' || v_msg."id"::text, (v_msg."tenant_id"::text)::text, null, 'better-supabase/messaging');
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_message_edit"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_msg."id";
    end if;
  end;
  return "better_supabase"."messaging_messages_json"(array[v_msg."id"]) -> 0;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.messaging_message_sent (
  message uuid
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_msg "better_supabase"."messages";
  v_conv "better_supabase"."conversations";
  v_mentioned uuid[];
  v_direct uuid[];
  v_claims text;
begin
  select * into v_msg from "better_supabase"."messages" m where m."id" = messaging_message_sent.message;
  select * into v_conv from "better_supabase"."conversations" c where c."id" = v_msg."conversation_id";
  perform "better_supabase"."index_record_mentions"(v_msg."id");
  perform "better_supabase".emit_event('message.sent', jsonb_build_object('organizationId', v_msg."tenant_id"::text, 'conversationId', v_msg."conversation_id", 'messageId', v_msg."id", 'authorId', v_msg."author_id", 'actorKind', v_msg."author_kind", 'actorName', v_msg."author_name", 'threadId', v_msg."thread_id", 'subjectType', 'message', 'subjectId', v_msg."id"::text, 'mentionIds', to_jsonb(v_msg."mentions"), 'recordMentions', (select coalesce(jsonb_agg(jsonb_build_object('type', x."subject_type", 'id', x."subject_id") order by x."subject_type", x."subject_id"), '[]'::jsonb) from "better_supabase"."message_record_mentions" x where x."message_id" = v_msg."id"))
      || coalesce((select jsonb_build_object('conversationKind', c."kind", 'recordType', c."subject_type", 'recordId', c."subject_id") from "better_supabase"."conversations" c where c."id" = v_msg."conversation_id"), '{}'::jsonb), 'messages/' || v_msg."id"::text, (v_msg."tenant_id"::text)::text, null, 'better-supabase/messaging');
  -- Mentioned users who can read the conversation.
  v_mentioned := array(
    select distinct x from unnest(v_msg."mentions") x
    where x is distinct from v_msg."author_id"
      and coalesce(better_supabase.can_user(x, 'tenant', v_msg."tenant_id", 'messages.read'), false)
        and (v_conv."access" <> 'members' or exists (select 1 from "better_supabase"."conversation_members" k where k."conversation_id" = v_conv."id" and k."user_id" = x))
        and (v_conv."access" <> 'subject' or case v_conv."subject_type" when 'message' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'conversation' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'channel' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'company' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'person' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'deal' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'course' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'post' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'activity' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'quote' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'work_item' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'employee' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'ledger_account' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'invoice' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'product' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'product_variant' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'rfq' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'till' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'order' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'calendar_event' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'booking' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'asset' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'asset_location' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'lease' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'expense_report' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'expense_line' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'donation_fund' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'warranty_claim' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'work_order' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'shipment' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'contract' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'control' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'compliance_policy' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'qualification_type' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'risk' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'case' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'inspection' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'inspection_program' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'inspection_finding' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'form' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'meeting' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'meeting_decision' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'maintenance_plan' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'dam_usage_right' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'lims_sample' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'tax_code' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'production_order' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'work_center' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'bank_account' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'care_plan' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'incident' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'advisory' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'advisory_product' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'vulnerability' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'content_entry' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'document' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'customer' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'drive_node' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'application' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) else true end)
  );
  if v_msg."mention_scope" is not null then
    v_mentioned := v_mentioned || array(
      select k."user_id" from "better_supabase"."conversation_members" k
      where k."conversation_id" = v_conv."id" and k."notify" <> 'none'
        and k."user_id" is distinct from v_msg."author_id"
    );
  end if;
  v_mentioned := array(
    select distinct x from unnest(v_mentioned) x
    where not exists (select 1 from "better_supabase"."conversation_members" k where k."conversation_id" = v_conv."id" and k."user_id" = x and k."notify" = 'none')
  );
  if cardinality(v_mentioned) > 0 then
    if better_supabase.import_run() is null then
      v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'message.mentioned',
      'tenant', v_msg."tenant_id",
      'actor', v_msg."author_id",
      'subject_type', 'message',
      'subject_id', coalesce(v_msg."thread_id", v_msg."id")::text,
      'subject_label', coalesce(case when v_conv."kind" = 'subject' then "better_supabase"."subject_title"(v_conv."subject_type", v_conv."subject_id") end, v_conv."title"),
      'summary', left(v_msg."body", 140),
      'data', jsonb_build_object('messageId', v_msg."id", 'conversationId', v_msg."conversation_id"),
      'recipients', to_jsonb(v_mentioned),
      'watchers', false,
      'key', 'message.mentioned:' || v_msg."id"::text
    ));
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
  end if;
  if v_conv."kind" in ('dm', 'group_dm') and v_msg."thread_id" is null then
    v_direct := array(
      select k."user_id" from "better_supabase"."conversation_members" k
      where k."conversation_id" = v_conv."id" and k."notify" = 'all'
        and k."user_id" is distinct from v_msg."author_id"
        and not k."user_id" = any (v_mentioned)
    );
    if cardinality(v_direct) > 0 then
      if better_supabase.import_run() is null then
      v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'message.direct',
      'tenant', v_msg."tenant_id",
      'actor', v_msg."author_id",
      'subject_type', 'message',
      'subject_id', coalesce(v_msg."thread_id", v_msg."id")::text,
      'subject_label', coalesce(case when v_conv."kind" = 'subject' then "better_supabase"."subject_title"(v_conv."subject_type", v_conv."subject_id") end, v_conv."title"),
      'summary', left(v_msg."body", 140),
      'data', jsonb_build_object('messageId', v_msg."id", 'conversationId', v_msg."conversation_id"),
      'recipients', to_jsonb(v_direct),
      'watchers', false,
      'key', 'message.direct:' || v_msg."id"::text
    ));
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
    end if;
  end if;
  if v_msg."thread_id" is not null then
    -- The replier and the root's author follow the thread.
    insert into "better_supabase"."notification_subscriptions" ("tenant_id", "user_id", "subject_type", "subject_id", "level")
    values (v_msg."tenant_id", v_msg."author_id", 'message', v_msg."thread_id"::text, 'participating')
    on conflict do nothing;
    insert into "better_supabase"."notification_subscriptions" ("tenant_id", "user_id", "subject_type", "subject_id", "level")
    values (v_msg."tenant_id", (select r."author_id" from "better_supabase"."messages" r where r."id" = v_msg."thread_id"), 'message', v_msg."thread_id"::text, 'participating')
    on conflict do nothing;
  end if;
  -- The thread's followers hear of a reply, less the members already told
  -- above; nothing is sent when no one follows it.
  if v_msg."thread_id" is not null and (exists (
      select 1 from "better_supabase"."notification_subscriptions" s
      where s."subject_type" = 'message' and s."subject_id" = v_msg."thread_id"::text and s."tenant_id" = v_msg."tenant_id"
        and s."level" in ('all', 'participating')
        and not s."user_id" = any (array[v_msg."author_id"] || v_mentioned)
    ) or to_regprocedure('"public"."notification_audience"(jsonb)') is not null) then
    if better_supabase.import_run() is null then
      v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'message.replied',
      'tenant', v_msg."tenant_id",
      'actor', v_msg."author_id",
      'subject_type', 'message',
      'subject_id', coalesce(v_msg."thread_id", v_msg."id")::text,
      'subject_label', coalesce(case when v_conv."kind" = 'subject' then "better_supabase"."subject_title"(v_conv."subject_type", v_conv."subject_id") end, v_conv."title"),
      'summary', left(v_msg."body", 140),
      'data', jsonb_build_object('messageId', v_msg."id", 'conversationId', v_msg."conversation_id"),
      'recipients', '[]'::jsonb,
      'exclude', to_jsonb(v_mentioned),
      'key', 'message.replied:' || v_msg."id"::text
    ));
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_message_send"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_msg."id";
    end if;
  end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.pin_message (
  message uuid,
  pinned  boolean DEFAULT true
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_msg "better_supabase"."messages";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_msg from "better_supabase"."messages" m
  where m."id" = pin_message.message and m."archived_at" is null and m."sent_at" is not null;
  if not found or not "better_supabase"."can_conversation"(v_msg."conversation_id", 'send') then
    raise exception 'no such message you can pin' using errcode = 'P0002', hint = 'MESSAGING_NOT_FOUND';
  end if;
  update "better_supabase"."messages" m
  set "pinned_at" = case when pin_message.pinned then coalesce(m."pinned_at", now()) end,
    "pinned_by" = case when pin_message.pinned then coalesce(m."pinned_by", auth.uid()) end
  where m."id" = v_msg."id"
  returning * into v_msg;
  perform "better_supabase".emit_event('message.pinned', jsonb_build_object('organizationId', v_msg."tenant_id"::text, 'conversationId', v_msg."conversation_id", 'messageId', v_msg."id", 'authorId', v_msg."author_id", 'actorKind', v_msg."author_kind", 'actorName', v_msg."author_name", 'threadId', v_msg."thread_id", 'subjectType', 'message', 'subjectId', v_msg."id"::text, 'pinned', pin_message.pinned)
      || coalesce((select jsonb_build_object('conversationKind', c."kind", 'recordType', c."subject_type", 'recordId', c."subject_id") from "better_supabase"."conversations" c where c."id" = v_msg."conversation_id"), '{}'::jsonb), 'messages/' || v_msg."id"::text, (v_msg."tenant_id"::text)::text, null, 'better-supabase/messaging');
  return "better_supabase"."messaging_messages_json"(array[v_msg."id"]) -> 0;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.resolve_message (
  message  uuid,
  resolved boolean DEFAULT true
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_msg "better_supabase"."messages";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_msg from "better_supabase"."messages" m
  where m."id" = resolve_message.message and m."thread_id" is null and m."archived_at" is null and m."sent_at" is not null;
  if not found or not "better_supabase"."can_conversation"(v_msg."conversation_id", 'send') then
    raise exception 'no such thread you can resolve' using errcode = 'P0002', hint = 'MESSAGING_NOT_FOUND';
  end if;
  update "better_supabase"."messages" m
  set "resolved_at" = case when resolve_message.resolved then coalesce(m."resolved_at", now()) end,
    "resolved_by" = case when resolve_message.resolved then coalesce(m."resolved_by", auth.uid()) end
  where m."id" = v_msg."id"
  returning * into v_msg;
  perform "better_supabase".emit_event('message.resolved', jsonb_build_object('organizationId', v_msg."tenant_id"::text, 'conversationId', v_msg."conversation_id", 'messageId', v_msg."id", 'authorId', v_msg."author_id", 'actorKind', v_msg."author_kind", 'actorName', v_msg."author_name", 'threadId', v_msg."thread_id", 'subjectType', 'message', 'subjectId', v_msg."id"::text, 'resolved', resolve_message.resolved)
      || coalesce((select jsonb_build_object('conversationKind', c."kind", 'recordType', c."subject_type", 'recordId', c."subject_id") from "better_supabase"."conversations" c where c."id" = v_msg."conversation_id"), '{}'::jsonb), 'messages/' || v_msg."id"::text, (v_msg."tenant_id"::text)::text, null, 'better-supabase/messaging');
  return "better_supabase"."messaging_messages_json"(array[v_msg."id"]) -> 0;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.send_message (
  conversation uuid,
  body         text,
  attrs        jsonb  DEFAULT '{}'::jsonb,
  attachments  uuid[] DEFAULT '{}'::uuid[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_conv "better_supabase"."conversations";
  v_id uuid;
  v_parent uuid := nullif(send_message.attrs ->> 'parentId', '')::uuid;
  v_root uuid;
  v_parsed jsonb := "better_supabase"."parse_mentions"(send_message.body);
  v_mentions uuid[];
  v_scheduled timestamptz := nullif(send_message.attrs ->> 'scheduledFor', '')::timestamptz;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_conv from "better_supabase"."conversations" c where c."id" = send_message.conversation;
  if not found or not "better_supabase"."can_conversation"(v_conv."id", 'read') then
    raise exception 'no such conversation you can read' using errcode = 'P0002', hint = 'MESSAGING_NOT_FOUND';
  end if;
  if v_conv."kind" = 'inbox' then
    raise exception 'write to an inbox conversation through send_inbox_message' using errcode = '42501', hint = 'MESSAGING_FORBIDDEN';
  end if;
  if v_conv."access" = 'tenant' and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and v_conv."archived_at" is null
    and coalesce(better_supabase.can('tenant', v_conv."tenant_id", 'messages.send'), false) then
    perform "better_supabase"."add_conversation_members"(v_conv."id", array[auth.uid()]);
  end if;
  if not "better_supabase"."can_conversation"(v_conv."id", 'send') then
    raise exception 'not allowed to send messages here' using errcode = '42501', hint = 'MESSAGING_FORBIDDEN';
  end if;
  if nullif(trim(coalesce(send_message.body, '')), '') is null and cardinality(coalesce(send_message.attachments, '{}')) = 0 then
    raise exception 'a message needs a body or a file' using errcode = '23502', hint = 'MESSAGING_BODY_REQUIRED';
  end if;
  if v_parent is not null then
    select m."thread_id" into v_root from "better_supabase"."messages" m
    where m."id" = v_parent and m."conversation_id" = v_conv."id"
      and m."sent_at" is not null and m."archived_at" is null;
    if not found then
      raise exception 'reply to a sent message in the same conversation' using errcode = '22023', hint = 'MESSAGING_PARENT_INVALID';
    end if;
    -- One level of threads: a reply to a reply joins the root's thread.
    v_parent := coalesce(v_root, v_parent);
  end if;
  if v_parent is null and send_message.attrs -> 'anchor' ->> 'kind' = 'file' then
    if not "better_supabase"."messaging_file_anchor_valid"(send_message.attrs -> 'anchor') then
      raise exception 'a file anchor needs an attachmentId, a page from 1, a region inside 0 to 1 and a time span from 0' using errcode = '22023', hint = 'MESSAGING_ANCHOR_INVALID';
    end if;
    if not exists (
      select 1 from "better_supabase"."attachments" a
      where a."id" = (send_message.attrs -> 'anchor' ->> 'attachmentId')::uuid
        and a."tenant_id" = v_conv."tenant_id"
        and a."status" <> 'infected'
        and ((a."subject_type" = v_conv."subject_type" and a."subject_id" = v_conv."subject_id")
          or (a."subject_type" = 'message' and exists (
            select 1 from "better_supabase"."messages" m
            where m."id"::text = a."subject_id" and m."conversation_id" = v_conv."id")))
    ) then
      raise exception 'anchor the message to a file on this record or in this conversation' using errcode = '22023', hint = 'MESSAGING_ANCHOR_INVALID';
    end if;
  end if;
  if v_scheduled is not null and v_scheduled <= now() then
    v_scheduled := null;
  end if;
  v_mentions := array(
    select distinct x from (
      select (jsonb_array_elements_text(coalesce(send_message.attrs -> 'mentions', '[]'::jsonb)))::uuid as x
      union
      select (jsonb_array_elements_text(v_parsed -> 'users'))::uuid
    ) s
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_message_send"(uuid, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::jsonb)', v_hook::oid::regproc)
        using send_message.conversation, send_message.body, send_message.attrs;
    end if;
  end;
  begin
    insert into "better_supabase"."messages" ("tenant_id", "conversation_id", "parent_id", "thread_id", "author_id", "author_kind", "author_name", "body", "document", "anchor",
      "mentions", "mention_scope", "broadcast", "scheduled_at", "sent_at")
    values (v_conv."tenant_id", v_conv."id", v_parent, case when v_parent is null then null else coalesce(v_root, v_parent) end,
      auth.uid(), case
      when send_message.attrs -> 'actor' ->> 'kind' ~ '^[a-z][a-z_-]{0,31}$' then send_message.attrs -> 'actor' ->> 'kind'
      when auth.jwt() -> 'act' ->> 'kind' = 'agent' then 'agent'
      when auth.role() = 'service_role' then 'service'
      when auth.uid() is null then 'system'
      else 'user' end, left(coalesce(nullif(send_message.attrs -> 'actor' ->> 'name', ''), auth.jwt() -> 'act' ->> 'name'), 120), coalesce(send_message.body, ''), send_message.attrs -> 'document',
      case when v_parent is null then send_message.attrs -> 'anchor' end, v_mentions,
      case when v_conv."access" = 'subject' then null else v_parsed ->> 'scope' end,
      v_parent is not null and coalesce((send_message.attrs ->> 'broadcast')::boolean, false),
      v_scheduled, case when v_scheduled is null then now() end)
    returning "id" into v_id;
  exception when check_violation or invalid_text_representation or datetime_field_overflow then
    raise exception 'a message field has an invalid value' using errcode = '22023', hint = 'MESSAGING_MESSAGE_INVALID';
  end;
  -- Files the caller uploaded to the conversation move onto the message.
  if cardinality(coalesce(send_message.attachments, '{}')) > 0 then
    update "better_supabase"."attachments" a
    set "subject_type" = 'message', "subject_id" = v_id::text
    where a."id" = any (send_message.attachments)
      and a."tenant_id" = v_conv."tenant_id"
      and a."subject_type" = 'conversation' and a."subject_id" = v_conv."id"::text
      and a."uploaded_by" = auth.uid()
      and a."status" <> 'infected';
    get diagnostics v_count = row_count;
    if v_count <> cardinality(array(select distinct x from unnest(send_message.attachments) x)) then
      raise exception 'attach files you uploaded to this conversation' using errcode = '22023', hint = 'MESSAGING_ATTACHMENT_INVALID';
    end if;
  end if;
  if v_scheduled is null then
    perform "better_supabase"."messaging_message_sent"(v_id);
  else
    perform "better_supabase"."enqueue_job"(queue => 'messaging', payload => jsonb_build_object('type', 'message.publish', 'messageId', v_id), delay => greatest(ceil(extract(epoch from (v_scheduled - now())))::integer, 0), dedupe_key => 'message.publish:' || v_id::text, dedupe_running => false);
    null;
  end if;
  return "better_supabase"."messaging_messages_json"(array[v_id]) -> 0;
end;
$function$;
