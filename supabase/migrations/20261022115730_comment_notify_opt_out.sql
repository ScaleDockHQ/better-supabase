SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.comment_sent (
  message uuid
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_msg record;
  v_conv record;
  v_user uuid;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_msg from "better_supabase"."messages" x
  where x."id" = comment_sent.message and x."author_id" = auth.uid()
    and x."sent_at" is not null and x."deleted_at" is null;
  if not found then
    return;
  end if;
  select * into v_conv from "better_supabase"."conversations" c
  where c."id" = v_msg."conversation_id" and c."kind" = 'subject';
  if not found then
    return;
  end if;
  foreach v_user in array array(select distinct x from unnest(array[v_msg."author_id"] || v_msg."mentions") x where x = v_msg."author_id" or coalesce(better_supabase.can_user(x, 'tenant', v_msg."tenant_id", 'messages.read'), false)) loop
    insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
    values (v_conv."tenant_id", v_user, v_conv."subject_type", v_conv."subject_id", 'participating')
    on conflict do nothing;
  end loop;
  if (exists (
      select 1 from "better_supabase"."notification_subscriptions" s
      where s."subject_type" = v_conv."subject_type" and s."subject_id" = v_conv."subject_id" and s."organization_id" = v_conv."tenant_id"
        and s."level" in ('all', 'participating')
        and not s."user_id" = any (array[v_msg."author_id"] || v_msg."mentions")
    ) or to_regprocedure('"public"."notification_audience"(jsonb)') is not null) then
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'comment.posted',
      'tenant', v_msg."tenant_id",
      'actor', v_msg."author_id",
      'subject_type', v_conv."subject_type",
      'subject_id', v_conv."subject_id",
      'subject_label', "better_supabase"."subject_title"(v_conv."subject_type", v_conv."subject_id"),
      'summary', left(v_msg."body", 140),
      'recipients', '[]'::jsonb,
      'exclude', to_jsonb(v_msg."mentions"),
      'key', 'comment.posted:' || v_msg."id"::text,
      'data', jsonb_build_object('messageId', v_msg."id", 'conversationId', v_msg."conversation_id")
    ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
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
  perform "better_supabase".emit_event('message.sent', jsonb_build_object('organizationId', v_msg."tenant_id"::text, 'conversationId', v_msg."conversation_id", 'messageId', v_msg."id", 'authorId', v_msg."author_id", 'threadId', v_msg."thread_id", 'subjectType', 'message', 'subjectId', v_msg."id"::text, 'mentionIds', to_jsonb(v_msg."mentions"), 'recordMentions', (select coalesce(jsonb_agg(jsonb_build_object('type', x."subject_type", 'id', x."subject_id") order by x."subject_type", x."subject_id"), '[]'::jsonb) from "better_supabase"."message_record_mentions" x where x."message_id" = v_msg."id"))
      || coalesce((select jsonb_build_object('conversationKind', c."kind", 'recordType', c."subject_type", 'recordId', c."subject_id") from "better_supabase"."conversations" c where c."id" = v_msg."conversation_id"), '{}'::jsonb), 'messages/' || v_msg."id"::text, (v_msg."tenant_id"::text)::text, null, 'better-supabase/messaging');
  -- Mentioned users who can read the conversation.
  v_mentioned := array(
    select distinct x from unnest(v_msg."mentions") x
    where x is distinct from v_msg."author_id"
      and coalesce(better_supabase.can_user(x, 'tenant', v_msg."tenant_id", 'messages.read'), false)
        and (v_conv."access" <> 'members' or exists (select 1 from "better_supabase"."conversation_members" k where k."conversation_id" = v_conv."id" and k."user_id" = x))
        and (v_conv."access" <> 'subject' or case v_conv."subject_type" when 'message' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'conversation' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'channel' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'company' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'person' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'deal' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'course' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'post' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'engagement' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'work_item' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'employee' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'ledger_account' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'product' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'product_variant' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'calendar_event' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'asset' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'asset_location' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'lease' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'maintenance_request' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'expense_report' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'expense_line' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'donation_fund' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'work_order' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'shipment' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'contract' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'control' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'policy' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'incident' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'document' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'customer' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'drive_node' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'application' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) else true end)
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
  if v_conv."kind" in ('dm', 'group_dm') and v_msg."thread_id" is null then
    v_direct := array(
      select k."user_id" from "better_supabase"."conversation_members" k
      where k."conversation_id" = v_conv."id" and k."notify" = 'all'
        and k."user_id" is distinct from v_msg."author_id"
        and not k."user_id" = any (v_mentioned)
    );
    if cardinality(v_direct) > 0 then
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
  if v_msg."thread_id" is not null then
    -- The replier and the root's author follow the thread.
    insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
    values (v_msg."tenant_id", v_msg."author_id", 'message', v_msg."thread_id"::text, 'participating')
    on conflict do nothing;
    insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
    values (v_msg."tenant_id", (select r."author_id" from "better_supabase"."messages" r where r."id" = v_msg."thread_id"), 'message', v_msg."thread_id"::text, 'participating')
    on conflict do nothing;
  end if;
  -- The thread's followers hear of a reply, less the members already told
  -- above; nothing is sent when no one follows it.
  if v_msg."thread_id" is not null and (exists (
      select 1 from "better_supabase"."notification_subscriptions" s
      where s."subject_type" = 'message' and s."subject_id" = v_msg."thread_id"::text and s."organization_id" = v_msg."tenant_id"
        and s."level" in ('all', 'participating')
        and not s."user_id" = any (array[v_msg."author_id"] || v_mentioned)
    ) or to_regprocedure('"public"."notification_audience"(jsonb)') is not null) then
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
