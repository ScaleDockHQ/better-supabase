SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.create_channel (
  tenant  uuid,
  name    text,
  attrs   jsonb  DEFAULT '{}'::jsonb,
  members uuid[] DEFAULT '{}'::uuid[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_name text := lower(trim(create_channel.name));
  v_visibility text := coalesce(create_channel.attrs ->> 'visibility', 'public');
  v_conv jsonb;
  v_ch "better_supabase"."channels";
  v_c "better_supabase"."conversations";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_channel.tenant, 'channels.create'), false)) then
    raise exception 'not allowed to create channels here' using errcode = '42501', hint = 'CHANNELS_FORBIDDEN';
  end if;
  if v_name is null or v_name !~ '^[a-z0-9][a-z0-9_-]{0,79}$' then
    raise exception 'a channel name is 1 to 80 lowercase letters, digits, - or _, starting with a letter or digit' using errcode = '22023', hint = 'CHANNELS_NAME_INVALID';
  end if;
  if v_visibility not in ('public', 'private') then
    raise exception 'a channel is public or private' using errcode = '22023', hint = 'CHANNELS_VISIBILITY_INVALID';
  end if;
  if (nullif(create_channel.attrs ->> 'subjectType', '') is null) <> (nullif(create_channel.attrs ->> 'subjectId', '') is null) then
    raise exception 'a linked record needs subjectType and subjectId' using errcode = '22023', hint = 'CHANNELS_SUBJECT_INVALID';
  end if;
  if nullif(create_channel.attrs ->> 'subjectType', '') is not null
    and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce("better_supabase"."can_subject"(create_channel.attrs ->> 'subjectType', create_channel.attrs ->> 'subjectId', 'read'), false)) then
    raise exception 'no such record you can read' using errcode = 'P0002', hint = 'CHANNELS_NOT_FOUND';
  end if;
  if coalesce((case (create_channel.attrs ->> 'subjectType')
      when 'message' then (select s."tenant_id"::text from "better_supabase"."messages" s where s."id" = ((create_channel.attrs ->> 'subjectId'))::uuid)
      when 'conversation' then (select s."tenant_id"::text from "better_supabase"."conversations" s where s."id" = ((create_channel.attrs ->> 'subjectId'))::uuid)
      when 'channel' then (select s."tenant_id"::text from "better_supabase"."channels" s where s."id" = ((create_channel.attrs ->> 'subjectId'))::uuid)
      when 'company' then (select s."tenant_id"::text from "better_supabase"."companies" s where s."id" = ((create_channel.attrs ->> 'subjectId'))::uuid)
      when 'person' then (select s."tenant_id"::text from "better_supabase"."people" s where s."id" = ((create_channel.attrs ->> 'subjectId'))::uuid)
      when 'deal' then (select s."tenant_id"::text from "better_supabase"."deals" s where s."id" = ((create_channel.attrs ->> 'subjectId'))::uuid)
      when 'course' then (select s."tenant_id"::text from "better_supabase"."courses" s where s."id" = ((create_channel.attrs ->> 'subjectId'))::uuid)
      when 'post' then (select s."tenant_id"::text from "better_supabase"."posts" s where s."id" = ((create_channel.attrs ->> 'subjectId'))::uuid)
      when 'engagement' then (select s."tenant_id"::text from "better_supabase"."engagements" s where s."id" = ((create_channel.attrs ->> 'subjectId'))::uuid)
      when 'work_item' then (select s."tenant_id"::text from "better_supabase"."work_items" s where s."id" = ((create_channel.attrs ->> 'subjectId'))::uuid)
      when 'employee' then (select s."tenant_id"::text from "better_supabase"."employees" s where s."id" = ((create_channel.attrs ->> 'subjectId'))::uuid)
      when 'ledger_account' then (select s."tenant_id"::text from "better_supabase"."ledger_accounts" s where s."id" = ((create_channel.attrs ->> 'subjectId'))::uuid)
      when 'product' then (select s."tenant_id"::text from "better_supabase"."products" s where s."id" = ((create_channel.attrs ->> 'subjectId'))::uuid)
      when 'product_variant' then (select s."tenant_id"::text from "better_supabase"."product_variants" s where s."id" = ((create_channel.attrs ->> 'subjectId'))::uuid)
      when 'calendar_event' then (select s."tenant_id"::text from "better_supabase"."calendar_events" s where s."id" = ((create_channel.attrs ->> 'subjectId'))::uuid)
      when 'asset' then (select s."tenant_id"::text from "better_supabase"."assets" s where s."id" = ((create_channel.attrs ->> 'subjectId'))::uuid)
      when 'asset_location' then (select s."tenant_id"::text from "better_supabase"."asset_locations" s where s."id" = ((create_channel.attrs ->> 'subjectId'))::uuid)
      when 'lease' then (select s."tenant_id"::text from "better_supabase"."lease_agreements" s where s."id" = ((create_channel.attrs ->> 'subjectId'))::uuid)
      when 'maintenance_request' then (select s."tenant_id"::text from "better_supabase"."maintenance_requests" s where s."id" = ((create_channel.attrs ->> 'subjectId'))::uuid)
      when 'expense_report' then (select s."tenant_id"::text from "better_supabase"."expense_reports" s where s."id" = ((create_channel.attrs ->> 'subjectId'))::uuid)
      when 'expense_line' then (select s."tenant_id"::text from "better_supabase"."expense_lines" s where s."id" = ((create_channel.attrs ->> 'subjectId'))::uuid)
      when 'donation_fund' then (select s."tenant_id"::text from "better_supabase"."donation_funds" s where s."id" = ((create_channel.attrs ->> 'subjectId'))::uuid)
      when 'work_order' then (select s."tenant_id"::text from "better_supabase"."work_orders" s where s."id" = ((create_channel.attrs ->> 'subjectId'))::uuid)
      when 'shipment' then (select s."tenant_id"::text from "better_supabase"."shipments" s where s."id" = ((create_channel.attrs ->> 'subjectId'))::uuid)
      when 'contract' then (select s."tenant_id"::text from "better_supabase"."contracts" s where s."id" = ((create_channel.attrs ->> 'subjectId'))::uuid)
      when 'control' then (select s."tenant_id"::text from "better_supabase"."controls" s where s."id" = ((create_channel.attrs ->> 'subjectId'))::uuid)
      when 'policy' then (select s."tenant_id"::text from "better_supabase"."policies" s where s."id" = ((create_channel.attrs ->> 'subjectId'))::uuid)
      when 'incident' then (select s."tenant_id"::text from "better_supabase"."incidents" s where s."id" = ((create_channel.attrs ->> 'subjectId'))::uuid)
      when 'document' then (select s."tenant_id"::text from "better_supabase"."documents" s where s."id" = ((create_channel.attrs ->> 'subjectId'))::uuid)
      when 'customer' then (select s."organization_id"::text from "public"."customers" s where s."id" = ((create_channel.attrs ->> 'subjectId'))::uuid)
      when 'drive_node' then (select s."tenant_id"::text from "better_supabase"."drive_nodes" s where s."id" = ((create_channel.attrs ->> 'subjectId'))::uuid)
      when 'application' then (select s."tenant_id"::text from "better_supabase"."applications" s where s."id" = ((create_channel.attrs ->> 'subjectId'))::uuid)
      when 'project' then (select s."organization_id"::text from "public"."projects" s where s."id" = ((create_channel.attrs ->> 'subjectId'))::uuid)
      when 'task' then (select s."organization_id"::text from "public"."tasks" s where s."id" = ((create_channel.attrs ->> 'subjectId'))::uuid)
      else null::text
    end) <> create_channel.tenant::text, false) then
    raise exception 'no such record in this organization' using errcode = 'P0002', hint = 'CHANNELS_NOT_FOUND';
  end if;
  if exists (select 1 from "better_supabase"."channels" x where x."tenant_id" = create_channel.tenant and x."name" = v_name) then
    raise exception 'a channel with this name exists' using errcode = '23505', hint = 'CHANNELS_NAME_TAKEN';
  end if;
  v_conv := "better_supabase"."open_conversation"(
    create_channel.tenant,
    'channel',
    jsonb_build_object('title', v_name, 'access', case v_visibility when 'public' then 'tenant' else 'members' end),
    create_channel.members
  );
  begin
    insert into "better_supabase"."channels" ("id", "tenant_id", "name", "visibility", "topic", "purpose", "subject_type", "subject_id", "created_by")
    values ((v_conv ->> 'id')::uuid, create_channel.tenant, v_name, v_visibility,
      nullif(trim(create_channel.attrs ->> 'topic'), ''), nullif(trim(create_channel.attrs ->> 'purpose'), ''),
      nullif(create_channel.attrs ->> 'subjectType', ''), nullif(create_channel.attrs ->> 'subjectId', ''), auth.uid())
    returning * into v_ch;
  exception
    when unique_violation then
      raise exception 'a channel with this name exists' using errcode = '23505', hint = 'CHANNELS_NAME_TAKEN';
    when check_violation then
      raise exception 'a channel field has an invalid value' using errcode = '22023', hint = 'CHANNELS_INVALID';
  end;
  perform "better_supabase".emit_event('channel.created', jsonb_build_object('organizationId', v_ch."tenant_id"::text, 'channelId', v_ch."id", 'name', v_ch."name", 'visibility', v_ch."visibility", 'recordType', v_ch."subject_type", 'recordId', v_ch."subject_id", 'subjectType', 'channel', 'subjectId', v_ch."id"::text), 'channels/' || v_ch."id"::text, (v_ch."tenant_id"::text)::text, null, 'better-supabase/channels');
  perform better_supabase.audit_event(
    event_type => 'channel.created',
    category => 'configuration',
    target_type => 'channel',
    record_id => v_ch."id"::text,
    target_label => v_ch."name",
    tenant => (v_ch."tenant_id"::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_ch."tenant_id"::text, 'channelId', v_ch."id", 'name', v_ch."name", 'visibility', v_ch."visibility", 'recordType', v_ch."subject_type", 'recordId', v_ch."subject_id", 'subjectType', 'channel', 'subjectId', v_ch."id"::text)
  );
  select * into v_c from "better_supabase"."conversations" c where c."id" = v_ch."id";
  return to_jsonb(v_ch) || jsonb_build_object(
      'archivedAt', v_c."archived_at",
      'lastMessageAt', v_c."last_message_at",
      'role', (select k."role" from "better_supabase"."conversation_members" k where k."conversation_id" = v_c."id" and k."user_id" = auth.uid()),
      'memberCount', (select count(*) from "better_supabase"."conversation_members" k where k."conversation_id" = v_c."id")
    );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.open_conversation (
  tenant  uuid,
  kind    text,
  attrs   jsonb  DEFAULT '{}'::jsonb,
  members uuid[] DEFAULT '{}'::uuid[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_users uuid[];
  v_key text;
  v_id uuid;
  v_access text;
  v_conv "better_supabase"."conversations";
  v_created boolean := false;
  v_guest boolean := open_conversation.kind = 'subject' and coalesce(((open_conversation.tenant)::text, (open_conversation.attrs ->> 'subjectType')::text, (open_conversation.attrs ->> 'subjectId')::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g), false);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', open_conversation.tenant, 'messages.send'), false) or v_guest) then
    raise exception 'not allowed to send messages here' using errcode = '42501', hint = 'MESSAGING_FORBIDDEN';
  end if;
  v_users := array(
    select distinct x from unnest(coalesce(open_conversation.members, '{}') || case when auth.uid() is null then '{}'::uuid[] else array[auth.uid()] end) x
    where x is not null order by 1
  );
  if not v_guest and exists (
    select 1 from unnest(v_users) x
    where not coalesce(better_supabase.can_user(x, 'tenant', open_conversation.tenant, 'messages.read'), false)
  ) then
    raise exception 'every member must be able to read messages in the organization' using errcode = '22023', hint = 'MESSAGING_MEMBER_INVALID';
  end if;
  case open_conversation.kind
    when 'dm', 'group_dm' then
      if open_conversation.kind = 'dm' and cardinality(v_users) not in (1, 2) then
        raise exception 'a direct message has one or two people' using errcode = '22023', hint = 'MESSAGING_DM_MEMBERS';
      end if;
      if open_conversation.kind = 'group_dm' and cardinality(v_users) not between 3 and 9 then
        raise exception 'a group message has three to nine people' using errcode = '22023', hint = 'MESSAGING_GROUP_MEMBERS';
      end if;
      v_key := array_to_string(v_users, ',');
      select c."id" into v_id from "better_supabase"."conversations" c
      where c."tenant_id" = open_conversation.tenant and c."kind" = open_conversation.kind and c."member_key" = v_key;
      v_access := 'members';
    when 'subject' then
      if nullif(open_conversation.attrs ->> 'subjectType', '') is null or nullif(open_conversation.attrs ->> 'subjectId', '') is null then
        raise exception 'a record conversation needs attrs.subjectType and attrs.subjectId' using errcode = '22023', hint = 'MESSAGING_SUBJECT_REQUIRED';
      end if;
      if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_guest or coalesce("better_supabase"."can_subject"(open_conversation.attrs ->> 'subjectType', open_conversation.attrs ->> 'subjectId', 'read'), false)) then
        raise exception 'no such record you can read' using errcode = 'P0002', hint = 'MESSAGING_NOT_FOUND';
      end if;
      -- A record with a tenant column takes conversations in its own tenant only.
      if coalesce((case (open_conversation.attrs ->> 'subjectType')
      when 'message' then (select s."tenant_id"::text from "better_supabase"."messages" s where s."id" = ((open_conversation.attrs ->> 'subjectId'))::uuid)
      when 'conversation' then (select s."tenant_id"::text from "better_supabase"."conversations" s where s."id" = ((open_conversation.attrs ->> 'subjectId'))::uuid)
      when 'channel' then (select s."tenant_id"::text from "better_supabase"."channels" s where s."id" = ((open_conversation.attrs ->> 'subjectId'))::uuid)
      when 'company' then (select s."tenant_id"::text from "better_supabase"."companies" s where s."id" = ((open_conversation.attrs ->> 'subjectId'))::uuid)
      when 'person' then (select s."tenant_id"::text from "better_supabase"."people" s where s."id" = ((open_conversation.attrs ->> 'subjectId'))::uuid)
      when 'deal' then (select s."tenant_id"::text from "better_supabase"."deals" s where s."id" = ((open_conversation.attrs ->> 'subjectId'))::uuid)
      when 'course' then (select s."tenant_id"::text from "better_supabase"."courses" s where s."id" = ((open_conversation.attrs ->> 'subjectId'))::uuid)
      when 'post' then (select s."tenant_id"::text from "better_supabase"."posts" s where s."id" = ((open_conversation.attrs ->> 'subjectId'))::uuid)
      when 'engagement' then (select s."tenant_id"::text from "better_supabase"."engagements" s where s."id" = ((open_conversation.attrs ->> 'subjectId'))::uuid)
      when 'work_item' then (select s."tenant_id"::text from "better_supabase"."work_items" s where s."id" = ((open_conversation.attrs ->> 'subjectId'))::uuid)
      when 'employee' then (select s."tenant_id"::text from "better_supabase"."employees" s where s."id" = ((open_conversation.attrs ->> 'subjectId'))::uuid)
      when 'ledger_account' then (select s."tenant_id"::text from "better_supabase"."ledger_accounts" s where s."id" = ((open_conversation.attrs ->> 'subjectId'))::uuid)
      when 'product' then (select s."tenant_id"::text from "better_supabase"."products" s where s."id" = ((open_conversation.attrs ->> 'subjectId'))::uuid)
      when 'product_variant' then (select s."tenant_id"::text from "better_supabase"."product_variants" s where s."id" = ((open_conversation.attrs ->> 'subjectId'))::uuid)
      when 'calendar_event' then (select s."tenant_id"::text from "better_supabase"."calendar_events" s where s."id" = ((open_conversation.attrs ->> 'subjectId'))::uuid)
      when 'asset' then (select s."tenant_id"::text from "better_supabase"."assets" s where s."id" = ((open_conversation.attrs ->> 'subjectId'))::uuid)
      when 'asset_location' then (select s."tenant_id"::text from "better_supabase"."asset_locations" s where s."id" = ((open_conversation.attrs ->> 'subjectId'))::uuid)
      when 'lease' then (select s."tenant_id"::text from "better_supabase"."lease_agreements" s where s."id" = ((open_conversation.attrs ->> 'subjectId'))::uuid)
      when 'maintenance_request' then (select s."tenant_id"::text from "better_supabase"."maintenance_requests" s where s."id" = ((open_conversation.attrs ->> 'subjectId'))::uuid)
      when 'expense_report' then (select s."tenant_id"::text from "better_supabase"."expense_reports" s where s."id" = ((open_conversation.attrs ->> 'subjectId'))::uuid)
      when 'expense_line' then (select s."tenant_id"::text from "better_supabase"."expense_lines" s where s."id" = ((open_conversation.attrs ->> 'subjectId'))::uuid)
      when 'donation_fund' then (select s."tenant_id"::text from "better_supabase"."donation_funds" s where s."id" = ((open_conversation.attrs ->> 'subjectId'))::uuid)
      when 'work_order' then (select s."tenant_id"::text from "better_supabase"."work_orders" s where s."id" = ((open_conversation.attrs ->> 'subjectId'))::uuid)
      when 'shipment' then (select s."tenant_id"::text from "better_supabase"."shipments" s where s."id" = ((open_conversation.attrs ->> 'subjectId'))::uuid)
      when 'contract' then (select s."tenant_id"::text from "better_supabase"."contracts" s where s."id" = ((open_conversation.attrs ->> 'subjectId'))::uuid)
      when 'control' then (select s."tenant_id"::text from "better_supabase"."controls" s where s."id" = ((open_conversation.attrs ->> 'subjectId'))::uuid)
      when 'policy' then (select s."tenant_id"::text from "better_supabase"."policies" s where s."id" = ((open_conversation.attrs ->> 'subjectId'))::uuid)
      when 'incident' then (select s."tenant_id"::text from "better_supabase"."incidents" s where s."id" = ((open_conversation.attrs ->> 'subjectId'))::uuid)
      when 'document' then (select s."tenant_id"::text from "better_supabase"."documents" s where s."id" = ((open_conversation.attrs ->> 'subjectId'))::uuid)
      when 'customer' then (select s."organization_id"::text from "public"."customers" s where s."id" = ((open_conversation.attrs ->> 'subjectId'))::uuid)
      when 'drive_node' then (select s."tenant_id"::text from "better_supabase"."drive_nodes" s where s."id" = ((open_conversation.attrs ->> 'subjectId'))::uuid)
      when 'application' then (select s."tenant_id"::text from "better_supabase"."applications" s where s."id" = ((open_conversation.attrs ->> 'subjectId'))::uuid)
      when 'project' then (select s."organization_id"::text from "public"."projects" s where s."id" = ((open_conversation.attrs ->> 'subjectId'))::uuid)
      when 'task' then (select s."organization_id"::text from "public"."tasks" s where s."id" = ((open_conversation.attrs ->> 'subjectId'))::uuid)
      else null::text
    end) <> open_conversation.tenant::text, false) then
        raise exception 'no such record in this organization' using errcode = 'P0002', hint = 'MESSAGING_NOT_FOUND';
      end if;
      select c."id" into v_id from "better_supabase"."conversations" c
      where c."tenant_id" = open_conversation.tenant and c."kind" = 'subject'
        and c."subject_type" = open_conversation.attrs ->> 'subjectType' and c."subject_id" = open_conversation.attrs ->> 'subjectId';
      v_access := 'subject';
      v_users := '{}';
    when 'channel' then
      v_access := coalesce(open_conversation.attrs ->> 'access', 'members');
      if v_access not in ('members', 'tenant') then
        raise exception 'a channel''s access is members or tenant' using errcode = '22023', hint = 'MESSAGING_ACCESS_INVALID';
      end if;
    when 'inbox' then
      if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
        raise exception 'the inbox opens its own conversations' using errcode = '42501', hint = 'MESSAGING_FORBIDDEN';
      end if;
      v_access := 'members';
    else
      raise exception 'kind is channel, dm, group_dm, subject or inbox' using errcode = '22023', hint = 'MESSAGING_KIND_INVALID';
  end case;
  if v_id is null then
    begin
      insert into "better_supabase"."conversations" ("tenant_id", "kind", "access", "subject_type", "subject_id", "title", "member_key", "created_by")
      values (open_conversation.tenant, open_conversation.kind, v_access,
        nullif(open_conversation.attrs ->> 'subjectType', ''), nullif(open_conversation.attrs ->> 'subjectId', ''),
        nullif(trim(open_conversation.attrs ->> 'title'), ''), v_key, auth.uid())
      returning "id" into v_id;
      v_created := true;
    exception when unique_violation then
      select c."id" into v_id from "better_supabase"."conversations" c
      where c."tenant_id" = open_conversation.tenant and c."kind" = open_conversation.kind
        and (c."member_key" = v_key or (c."subject_type" = open_conversation.attrs ->> 'subjectType' and c."subject_id" = open_conversation.attrs ->> 'subjectId'));
    when check_violation then
      raise exception 'a conversation field has an invalid value' using errcode = '22023', hint = 'MESSAGING_CONVERSATION_INVALID';
    end;
  end if;
  select * into v_conv from "better_supabase"."conversations" c where c."id" = v_id;
  if v_created then
    insert into "better_supabase"."conversation_members" ("conversation_id", "tenant_id", "user_id", "role")
    select v_id, open_conversation.tenant, x, case when x = auth.uid() then 'owner' else 'member' end from unnest(v_users) x
    on conflict do nothing;
    perform "better_supabase".emit_event('conversation.created', jsonb_build_object('organizationId', v_conv."tenant_id"::text, 'conversationId', v_conv."id", 'kind', v_conv."kind", 'subjectType', 'conversation', 'subjectId', v_conv."id"::text, 'recordType', v_conv."subject_type", 'recordId', v_conv."subject_id"), 'conversations/' || v_conv."id"::text, (v_conv."tenant_id"::text)::text, null, 'better-supabase/messaging');
  end if;
  return to_jsonb(v_conv);
end;
$function$;
