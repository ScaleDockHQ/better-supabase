import type { InboxSql } from "./inbox-names.ts";

import { sqlString } from "../../core/template.ts";

export const forbidden = (what: string): string =>
  `raise exception '${what}' using errcode = '42501', hint = 'INBOX_FORBIDDEN';`;
export const missing = (what: string, hint: string): string =>
  `raise exception '${what} not found' using errcode = 'P0002', hint = '${hint}';`;

/** The SQL functions: the writes and the reads with joined rows. */
export function inboxFunctions(q: InboxSql): string {
  const { id, fn } = q;
  const ib = q.cols("inboxes");
  const mb = q.cols("members");
  const tm = q.cols("teams");
  const tmm = q.cols("teamMembers");
  const ct = q.cols("contacts");
  const ci = q.cols("identities");
  const cv = q.cols("conversations");
  const pa = q.cols("participants");
  const ev = q.cols("events");
  const rd = q.cols("reads");
  const ms = q.cols("messages");
  const dl = q.cols("deliveries");
  const mn = q.cols("mentions");
  const T = (name: string): string => q.t(name);
  const service = q.service;
  const authed = (signature: string): string =>
    `revoke execute on function ${signature} from public, anon;
grant execute on function ${signature} to authenticated, service_role;`;
  const serviceOnly = (signature: string): string =>
    `revoke execute on function ${signature} from public, anon, authenticated;
grant execute on function ${signature} to service_role;`;
  const internal = (signature: string): string =>
    `revoke execute on function ${signature} from public, anon, authenticated;`;

  const ctx = q.ctx;
  const notifyOn = ctx.installed("notifications") && ctx.flag("notify", true);
  // notify() trusts only the service role, so the module sends as it with
  // the acting user as the actor, then restores the caller's claims.
  const notify = (fields: string): string =>
    notifyOn
      ? `
  v_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
  perform ${ctx.of("notifications").fn("notify")}(${fields});
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);`
      : "";
  const notifyDeclare = notifyOn ? "\n  v_claims text;" : "";
  const enqueue = (queue: string, payload: string, dedupe: string): string =>
    `perform ${ctx.of("jobs").fn("enqueue_job")}(${sqlString(queue)}, ${payload}, 0, 5, ${dedupe}, false);`;
  const conversationEvent = (type: string, extra: string): string =>
    ctx.emit({
      type,
      payload: `jsonb_build_object('conversationId', v_conv.${cv("id")}, 'organizationId', v_conv.${cv("tenant")}::text, 'inboxId', v_conv.${cv("inbox")}, 'contactId', v_conv.${cv("contact")}, 'assigneeId', v_conv.${cv("assignee")}, 'status', v_conv.${cv("status")}${extra})`,
      subject: `'conversations/' || v_conv.${cv("id")}::text`,
      tenant: `v_conv.${cv("tenant")}`,
    });
  const received = ctx.emit({
    type: "inbox.message.received",
    payload: `jsonb_build_object('conversationId', v_conv.${cv("id")}, 'organizationId', v_conv.${cv("tenant")}::text, 'messageId', v_msg.${ms("id")}, 'inboxId', v_conv.${cv("inbox")}, 'contactId', v_conv.${cv("contact")})`,
    subject: `'conversations/' || v_conv.${cv("id")}::text`,
    tenant: `v_conv.${cv("tenant")}`,
  });
  const log = (type: string, data = "'{}'::jsonb"): string =>
    `insert into ${T("events")} (${ev("tenant")}, ${ev("conversation")}, ${ev("type")}, ${ev("actor")}, ${ev("data")})
  values (v_conv.${cv("tenant")}, v_conv.${cv("id")}, ${sqlString(type)}, (select auth.uid()), ${data});`;
  // Who to tell about the conversation: the assignee, or the inbox's members
  // while nobody is assigned.
  const audience = `case when v_conv.${cv("assignee")} is not null then to_jsonb(array[v_conv.${cv("assignee")}])
    else coalesce((select jsonb_agg(m.${mb("user")}) from ${T("members")} m where m.${mb("inbox")} = v_conv.${cv("inbox")}), '[]'::jsonb) end`;
  const conversationJson = fn("inbox_conversation_json");
  const staffCan = (action: "read" | "reply" | "assign" | "manage"): string =>
    q.can(`v_conv.${cv("tenant")}`, action);
  const loadConversation = (
    param: string,
  ): string => `select * into v_conv from ${T("conversations")} where ${cv("id")} = ${param} for update;
  if not found then
    ${missing("conversation", "CONVERSATION_NOT_FOUND")}
  end if;`;

  return `-- A conversation with its contact and inbox, as the reads return it.
create or replace function ${conversationJson}(conversation uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select to_jsonb(v) || jsonb_build_object(
    'contact', (select jsonb_build_object('id', c.${ct("id")}, 'name', c.${ct("name")}, 'email', c.${ct("email")}, 'phone', c.${ct("phone")}, 'avatar_url', c.${ct("avatarUrl")}, 'user_id', c.${ct("user")}) from ${T("contacts")} c where c.${ct("id")} = v.${cv("contact")}),
    'inbox', (select jsonb_build_object('id', i.${ib("id")}, 'name', i.${ib("name")}, 'channel', i.${ib("channel")}) from ${T("inboxes")} i where i.${ib("id")} = v.${cv("inbox")}),
    'last_read_at', (select r.${rd("lastReadAt")} from ${T("reads")} r where r.${rd("conversation")} = v.${cv("id")} and r.${rd("user")} = (select auth.uid()))
  )
  from ${T("conversations")} v
  where v.${cv("id")} = conversation;
$$;
${authed(`${conversationJson}(uuid)`)}

create or replace function ${fn("create_inbox")}(tenant ${id}, name text, channel text default 'in_app', settings jsonb default '{}'::jsonb, bot_mode text default 'human', address text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${T("inboxes")}%rowtype;
begin
  if not (${service} or ${q.can("create_inbox.tenant", "manage")}) then
    ${forbidden("not allowed to manage inboxes")}
  end if;
  insert into ${T("inboxes")} (${ib("tenant")}, ${ib("name")}, ${ib("channel")}, ${ib("settings")}, ${ib("botMode")}, ${ib("address")})
  values (create_inbox.tenant, create_inbox.name, coalesce(create_inbox.channel, 'in_app'), coalesce(create_inbox.settings, '{}'::jsonb), coalesce(create_inbox.bot_mode, 'human'), create_inbox.address)
  returning * into v_row;
  return to_jsonb(v_row);
end;
$$;
${authed(`${fn("create_inbox")}(${id}, text, text, jsonb, text, text)`)}

-- patch keys: name, settings (merged), bot_mode, address, installation_id,
-- archived (true archives, false restores).
create or replace function ${fn("update_inbox")}(inbox uuid, patch jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${T("inboxes")}%rowtype;
begin
  select * into v_row from ${T("inboxes")} where ${ib("id")} = update_inbox.inbox for update;
  if not found then
    ${missing("inbox", "INBOX_NOT_FOUND")}
  end if;
  if not (${service} or ${q.can(`v_row.${ib("tenant")}`, "manage")}) then
    ${forbidden("not allowed to manage inboxes")}
  end if;
  update ${T("inboxes")} set
    ${ib("name")} = coalesce(patch ->> 'name', ${ib("name")}),
    ${ib("settings")} = ${ib("settings")} || coalesce(patch -> 'settings', '{}'::jsonb),
    ${ib("botMode")} = coalesce(patch ->> 'bot_mode', ${ib("botMode")}),
    ${ib("address")} = case when patch ? 'address' then patch ->> 'address' else ${ib("address")} end,
    ${ib("installation")} = case when patch ? 'installation_id' then (patch ->> 'installation_id')::uuid else ${ib("installation")} end,
    ${ib("archivedAt")} = case when patch ? 'archived' then (case when (patch ->> 'archived')::boolean then coalesce(${ib("archivedAt")}, now()) end) else ${ib("archivedAt")} end
  where ${ib("id")} = update_inbox.inbox
  returning * into v_row;
  return to_jsonb(v_row);
end;
$$;
${authed(`${fn("update_inbox")}(uuid, jsonb)`)}

-- Adds or updates a member; a null role removes them.
create or replace function ${fn("set_inbox_member")}(inbox uuid, member uuid, role text default 'agent')
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${id};
begin
  select ${ib("tenant")} into v_tenant from ${T("inboxes")} where ${ib("id")} = set_inbox_member.inbox;
  if not found then
    ${missing("inbox", "INBOX_NOT_FOUND")}
  end if;
  if not (${service} or ${q.can("v_tenant", "manage")}) then
    ${forbidden("not allowed to manage inboxes")}
  end if;
  if role is null then
    delete from ${T("members")} m where m.${mb("inbox")} = set_inbox_member.inbox and m.${mb("user")} = member;
    return found;
  end if;
  if not coalesce(better_supabase.can_user(member, 'tenant', v_tenant, ${q.key("read")}), false) then
    raise exception 'user cannot read this inbox' using errcode = '22023', hint = 'INBOX_MEMBER_INVALID';
  end if;
  insert into ${T("members")} (${mb("inbox")}, ${mb("user")}, ${mb("role")}) values (set_inbox_member.inbox, member, role)
  on conflict (${mb("inbox")}, ${mb("user")}) do update set ${mb("role")} = excluded.${mb("role")};
  return true;
end;
$$;
${authed(`${fn("set_inbox_member")}(uuid, uuid, text)`)}

create or replace function ${fn("create_inbox_team")}(tenant ${id}, name text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${T("teams")}%rowtype;
begin
  if not (${service} or ${q.can("create_inbox_team.tenant", "manage")}) then
    ${forbidden("not allowed to manage inboxes")}
  end if;
  insert into ${T("teams")} (${tm("tenant")}, ${tm("name")}) values (create_inbox_team.tenant, create_inbox_team.name)
  returning * into v_row;
  return to_jsonb(v_row);
end;
$$;
${authed(`${fn("create_inbox_team")}(${id}, text)`)}

create or replace function ${fn("set_inbox_team_member")}(team uuid, member uuid, present boolean default true)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${id};
begin
  select ${tm("tenant")} into v_tenant from ${T("teams")} where ${tm("id")} = set_inbox_team_member.team;
  if not found then
    ${missing("team", "INBOX_TEAM_NOT_FOUND")}
  end if;
  if not (${service} or ${q.can("v_tenant", "manage")}) then
    ${forbidden("not allowed to manage inboxes")}
  end if;
  if not coalesce(present, true) then
    delete from ${T("teamMembers")} t where t.${tmm("team")} = set_inbox_team_member.team and t.${tmm("user")} = member;
    return found;
  end if;
  insert into ${T("teamMembers")} (${tmm("team")}, ${tmm("user")}) values (set_inbox_team_member.team, member)
  on conflict do nothing;
  return true;
end;
$$;
${authed(`${fn("set_inbox_team_member")}(uuid, uuid, boolean)`)}

-- Finds or creates a contact: by id, then by the identity on a channel, the
-- signed-in user, then the email. Fields in input fill in what is missing;
-- an identity is attached when given. No permission check: callers check.
create or replace function ${fn("inbox_resolve_contact")}(tenant ${id}, input jsonb)
returns ${T("contacts")}
language plpgsql
set search_path = ''
as $$
declare
  v_contact ${T("contacts")}%rowtype;
  v_identity jsonb := input -> 'identity';
begin
  if input ? 'id' then
    select * into v_contact from ${T("contacts")} c where c.${ct("id")} = (input ->> 'id')::uuid and c.${ct("tenant")} = inbox_resolve_contact.tenant;
    if not found then
      ${missing("contact", "CONTACT_NOT_FOUND")}
    end if;
  end if;
  if v_contact.${ct("id")} is null and v_identity is not null then
    select c.* into v_contact from ${T("identities")} i join ${T("contacts")} c on c.${ct("id")} = i.${ci("contact")}
    where i.${ci("tenant")} = inbox_resolve_contact.tenant and i.${ci("channel")} = v_identity ->> 'channel' and i.${ci("externalId")} = v_identity ->> 'external_id';
  end if;
  if v_contact.${ct("id")} is null and input ? 'user_id' then
    select * into v_contact from ${T("contacts")} c where c.${ct("tenant")} = inbox_resolve_contact.tenant and c.${ct("user")} = (input ->> 'user_id')::uuid;
  end if;
  if v_contact.${ct("id")} is null and nullif(input ->> 'email', '') is not null then
    select * into v_contact from ${T("contacts")} c where c.${ct("tenant")} = inbox_resolve_contact.tenant and lower(c.${ct("email")}) = lower(input ->> 'email')
    order by c.${ct("createdAt")} limit 1;
  end if;
  if v_contact.${ct("id")} is null then
    insert into ${T("contacts")} (${ct("tenant")}, ${ct("user")}, ${ct("name")}, ${ct("email")}, ${ct("phone")}, ${ct("avatarUrl")}, ${ct("metadata")})
    values (inbox_resolve_contact.tenant, (input ->> 'user_id')::uuid, input ->> 'name', input ->> 'email', input ->> 'phone', input ->> 'avatar_url', coalesce(input -> 'metadata', '{}'::jsonb))
    returning * into v_contact;
  else
    update ${T("contacts")} c set
      ${ct("name")} = coalesce(c.${ct("name")}, input ->> 'name'),
      ${ct("email")} = coalesce(c.${ct("email")}, input ->> 'email'),
      ${ct("phone")} = coalesce(c.${ct("phone")}, input ->> 'phone'),
      ${ct("avatarUrl")} = coalesce(input ->> 'avatar_url', c.${ct("avatarUrl")}),
      ${ct("user")} = coalesce(c.${ct("user")}, (input ->> 'user_id')::uuid),
      ${ct("metadata")} = c.${ct("metadata")} || coalesce(input -> 'metadata', '{}'::jsonb)
    where c.${ct("id")} = v_contact.${ct("id")}
    returning * into v_contact;
  end if;
  if v_identity is not null and v_identity ? 'channel' and v_identity ? 'external_id' then
    insert into ${T("identities")} (${ci("tenant")}, ${ci("contact")}, ${ci("channel")}, ${ci("externalId")})
    values (inbox_resolve_contact.tenant, v_contact.${ct("id")}, v_identity ->> 'channel', v_identity ->> 'external_id')
    on conflict do nothing;
  end if;
  return v_contact;
end;
$$;
${internal(`${fn("inbox_resolve_contact")}(${id}, jsonb)`)}

create or replace function ${fn("upsert_contact")}(tenant ${id}, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (${service} or ${q.can("upsert_contact.tenant", "reply")}) then
    ${forbidden("not allowed to edit contacts")}
  end if;
  return to_jsonb(${fn("inbox_resolve_contact")}(upsert_contact.tenant, coalesce(input, '{}'::jsonb)));
end;
$$;
${authed(`${fn("upsert_contact")}(${id}, jsonb)`)}

-- Stores a message on a conversation and moves the conversation along: the
-- preview, the first response, a reopen when the contact writes, mentions,
-- the bot job, the outbound job and the notifications. Callers check access.
create or replace function ${fn("inbox_add_message")}(conversation uuid, input jsonb, author_type text, author uuid, direction text)
returns ${T("messages")}
language plpgsql
set search_path = ''
as $$
declare
  v_conv ${T("conversations")}%rowtype;
  v_inbox ${T("inboxes")}%rowtype;
  v_msg ${T("messages")}%rowtype;
  v_kind text := coalesce(input ->> 'kind', 'message');
  v_mentions uuid[];
  v_reopened boolean := false;${notifyDeclare}
begin
  select * into v_conv from ${T("conversations")} where ${cv("id")} = inbox_add_message.conversation for update;
  select * into v_inbox from ${T("inboxes")} where ${ib("id")} = v_conv.${cv("inbox")};
  if input ? 'external_id' then
    select * into v_msg from ${T("messages")} m
    where m.${ms("conversation")} = v_conv.${cv("id")} and m.${ms("externalId")} = input ->> 'external_id';
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
  where coalesce(better_supabase.can_user(u.x, 'tenant', v_conv.${cv("tenant")}, ${q.key("read")}), false);
  insert into ${T("messages")} (${ms("tenant")}, ${ms("conversation")}, ${ms("direction")}, ${ms("kind")}, ${ms("authorType")}, ${ms("author")}, ${ms("body")}, ${ms("format")}, ${ms("attachments")}, ${ms("mentions")}, ${ms("externalId")}, ${ms("replyTo")}, ${ms("metadata")})
  values (
    v_conv.${cv("tenant")}, v_conv.${cv("id")}, inbox_add_message.direction, v_kind, inbox_add_message.author_type, inbox_add_message.author,
    coalesce(input ->> 'body', ''), coalesce(input ->> 'format', 'text'), coalesce(input -> 'attachments', '[]'::jsonb), v_mentions,
    input ->> 'external_id', (input ->> 'reply_to')::uuid, coalesce(input -> 'metadata', '{}'::jsonb)
  )
  returning * into v_msg;
  insert into ${T("mentions")} (${mn("message")}, ${mn("user")}, ${mn("tenant")})
  select v_msg.${ms("id")}, x, v_msg.${ms("tenant")} from unnest(v_mentions) x
  on conflict do nothing;
  if v_kind = 'message' then
    v_reopened := inbox_add_message.direction = 'inbound' and v_conv.${cv("status")} in ('resolved', 'snoozed');
    update ${T("conversations")} set
      ${cv("lastMessageAt")} = v_msg.${ms("createdAt")},
      ${cv("preview")} = left(v_msg.${ms("body")}, 140),
      ${cv("firstResponseAt")} = case
        when ${cv("firstResponseAt")} is null and inbox_add_message.direction = 'outbound' and inbox_add_message.author_type in ('agent', 'bot') then v_msg.${ms("createdAt")}
        else ${cv("firstResponseAt")} end,
      ${cv("status")} = case when v_reopened then 'open' else ${cv("status")} end,
      ${cv("snoozedUntil")} = case when v_reopened then null else ${cv("snoozedUntil")} end,
      ${cv("resolvedAt")} = case when v_reopened then null else ${cv("resolvedAt")} end
    where ${cv("id")} = v_conv.${cv("id")}
    returning * into v_conv;
    if v_reopened then
      ${log("reopened", "jsonb_build_object('by', 'contact')")}
      ${conversationEvent("inbox.conversation.reopened", "")}
    end if;
  end if;
  if inbox_add_message.author is not null and inbox_add_message.author_type = 'agent' then
    insert into ${T("participants")} (${pa("conversation")}, ${pa("user")}) values (v_conv.${cv("id")}, inbox_add_message.author)
    on conflict do nothing;
  end if;
  if v_kind = 'message' and inbox_add_message.direction = 'inbound' then
    ${received}
    if v_conv.${cv("botMode")} = 'bot' then
      ${enqueue(q.botQueue, `jsonb_build_object('conversation_id', v_conv.${cv("id")}, 'message_id', v_msg.${ms("id")}, 'thread_id', v_conv.${cv("thread")}, 'inbox_id', v_conv.${cv("inbox")})`, `'inbox:' || v_conv.${cv("id")}::text`)}
    end if;${notify(`jsonb_build_object(
      'type', 'inbox.message',
      'tenant', v_conv.${cv("tenant")},
      'subject_type', 'conversation',
      'subject_id', v_conv.${cv("id")}::text,
      'summary', left(v_msg.${ms("body")}, 140),
      'recipients', ${audience},
      'key', 'inbox.message:' || v_msg.${ms("id")}::text,
      'data', jsonb_build_object('conversationId', v_conv.${cv("id")}, 'messageId', v_msg.${ms("id")})
    )`)}
  end if;
  if v_kind = 'message' and inbox_add_message.direction = 'outbound' and v_inbox.${ib("channel")} <> 'in_app' then
    insert into ${T("deliveries")} (${dl("tenant")}, ${dl("message")}, ${dl("channel")})
    values (v_msg.${ms("tenant")}, v_msg.${ms("id")}, v_inbox.${ib("channel")})
    on conflict do nothing;
    if not coalesce((input ->> 'delivered_by_caller')::boolean, false) then
      ${enqueue(q.outboundQueue, `jsonb_build_object('message_id', v_msg.${ms("id")}, 'conversation_id', v_conv.${cv("id")}, 'inbox_id', v_conv.${cv("inbox")})`, `'inbox-out:' || v_msg.${ms("id")}::text`)}
    end if;
  end if;${
    notifyOn
      ? `
  if cardinality(v_mentions) > 0 then${notify(`jsonb_build_object(
      'type', 'inbox.mention',
      'tenant', v_conv.${cv("tenant")},
      'actor', inbox_add_message.author,
      'subject_type', 'conversation',
      'subject_id', v_conv.${cv("id")}::text,
      'summary', left(v_msg.${ms("body")}, 140),
      'recipients', to_jsonb(v_mentions),
      'key', 'inbox.mention:' || v_msg.${ms("id")}::text,
      'data', jsonb_build_object('conversationId', v_conv.${cv("id")}, 'messageId', v_msg.${ms("id")})
    )`)}
  end if;`
      : ""
  }
  return v_msg;
end;
$$;
${internal(`${fn("inbox_add_message")}(uuid, jsonb, text, uuid, text)`)}

-- Opens a conversation. Staff (the reply key) or the service name the
-- contact in input.contact (an id or the fields inbox_resolve_contact
-- takes); a signed-in visitor of an in-app inbox with settings.widget = true
-- opens one as themselves. input.message adds the first message.
create or replace function ${fn("start_conversation")}(inbox uuid, input jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inbox ${T("inboxes")}%rowtype;
  v_contact ${T("contacts")}%rowtype;
  v_conv ${T("conversations")}%rowtype;
  v_staff boolean;
  v_contact_input jsonb := coalesce(input -> 'contact', '{}'::jsonb);
begin
  select * into v_inbox from ${T("inboxes")} where ${ib("id")} = start_conversation.inbox and ${ib("archivedAt")} is null;
  if not found then
    ${missing("inbox", "INBOX_NOT_FOUND")}
  end if;
  v_staff := ${service} or ${q.can(`v_inbox.${ib("tenant")}`, "reply")};
  if v_staff then
    if jsonb_typeof(input -> 'contact') = 'string' then
      v_contact_input := jsonb_build_object('id', input ->> 'contact');
    end if;
    if v_contact_input = '{}'::jsonb then
      raise exception 'input.contact is required' using errcode = '22023', hint = 'CONTACT_REQUIRED';
    end if;
  elsif (select auth.uid()) is not null and v_inbox.${ib("channel")} = 'in_app' and coalesce((v_inbox.${ib("settings")} ->> 'widget')::boolean, false) then
    v_contact_input := jsonb_build_object(
      'user_id', (select auth.uid()),
      'name', v_contact_input ->> 'name',
      'email', coalesce((select auth.jwt()) ->> 'email', v_contact_input ->> 'email')
    );
  else
    ${forbidden("not allowed to open a conversation in this inbox")}
  end if;
  v_contact := ${fn("inbox_resolve_contact")}(v_inbox.${ib("tenant")}, v_contact_input);
  insert into ${T("conversations")} (${cv("tenant")}, ${cv("inbox")}, ${cv("contact")}, ${cv("subject")}, ${cv("priority")}, ${cv("botMode")}, ${cv("thread")}, ${cv("assignee")}, ${cv("metadata")})
  values (
    v_inbox.${ib("tenant")}, v_inbox.${ib("id")}, v_contact.${ct("id")}, input ->> 'subject', coalesce(input ->> 'priority', 'normal'),
    coalesce(input ->> 'bot_mode', v_inbox.${ib("botMode")}), input ->> 'thread_id',
    case when v_staff then (input ->> 'assignee_id')::uuid end, coalesce(input -> 'metadata', '{}'::jsonb)
  )
  returning * into v_conv;
  if v_conv.${cv("thread")} is null then
    update ${T("conversations")} set ${cv("thread")} = ${sqlString(`${q.topic}:`)} || ${cv("id")}::text
    where ${cv("id")} = v_conv.${cv("id")}
    returning * into v_conv;
  end if;
  ${log("opened")}
  ${conversationEvent("inbox.conversation.opened", "")}
  if input ? 'message' then
    perform ${fn("inbox_add_message")}(
      v_conv.${cv("id")},
      case when jsonb_typeof(input -> 'message') = 'string' then jsonb_build_object('body', input ->> 'message') else input -> 'message' end,
      case when v_staff then (case when (select auth.uid()) is null then 'bot' else 'agent' end) else 'contact' end,
      (select auth.uid()),
      case when v_staff then 'outbound' else 'inbound' end
    );
  end if;
  return ${conversationJson}(v_conv.${cv("id")});
end;
$$;
${authed(`${fn("start_conversation")}(uuid, jsonb)`)}

-- Staff reply or add a note (input.kind = 'note'); the contact writes in
-- their own conversation; the service writes as the bot, the system, or the
-- contact (input.author_type). An agent's reply hands a bot conversation
-- over to staff.
create or replace function ${fn("send_message")}(conversation uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_conv ${T("conversations")}%rowtype;
  v_msg ${T("messages")}%rowtype;
  v_author_type text;
  v_direction text;
  v_kind text := coalesce(input ->> 'kind', 'message');
begin
  ${loadConversation("send_message.conversation")}
  if ${service} then
    v_author_type := coalesce(input ->> 'author_type', 'bot');
    v_direction := case when v_author_type = 'contact' then 'inbound' else 'outbound' end;
  elsif ${staffCan("reply")} then
    v_author_type := 'agent';
    v_direction := 'outbound';
  elsif exists (select 1 from ${T("contacts")} c where c.${ct("id")} = v_conv.${cv("contact")} and c.${ct("user")} = (select auth.uid())) then
    if v_kind <> 'message' then
      ${forbidden("contacts cannot write notes")}
    end if;
    v_author_type := 'contact';
    v_direction := 'inbound';
  else
    ${forbidden("not allowed to write in this conversation")}
  end if;
  v_msg := ${fn("inbox_add_message")}(v_conv.${cv("id")}, coalesce(input, '{}'::jsonb) - 'author_type', v_author_type, (select auth.uid()), v_direction);
  if v_author_type = 'agent' and v_kind = 'message' and v_conv.${cv("botMode")} = 'bot' then
    update ${T("conversations")} set ${cv("botMode")} = 'human' where ${cv("id")} = v_conv.${cv("id")} returning * into v_conv;
    ${log("handoff", "jsonb_build_object('from', 'bot', 'to', 'human', 'reason', 'agent_reply')")}
  end if;
  return to_jsonb(v_msg);
end;
$$;
${authed(`${fn("send_message")}(uuid, jsonb)`)}

-- A message that arrived on a channel, for the inbound handler: finds the
-- inbox's conversation for the thread (reopening it) or opens one, resolves
-- the contact by its identity on the channel, and stores the message once
-- per external_id. Returns { conversation_id, message_id, contact_id,
-- created, duplicate }.
create or replace function ${fn("record_inbound")}(input jsonb)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_inbox ${T("inboxes")}%rowtype;
  v_contact ${T("contacts")}%rowtype;
  v_conv ${T("conversations")}%rowtype;
  v_msg ${T("messages")}%rowtype;
  v_created boolean := false;
  v_duplicate boolean := false;
  v_message jsonb := coalesce(input -> 'message', '{}'::jsonb);
  v_contact_input jsonb := coalesce(input -> 'contact', '{}'::jsonb);
begin
  select * into v_inbox from ${T("inboxes")} where ${ib("id")} = (input ->> 'inbox_id')::uuid;
  if not found then
    ${missing("inbox", "INBOX_NOT_FOUND")}
  end if;
  if v_contact_input ? 'external_id' and not v_contact_input ? 'identity' then
    v_contact_input := v_contact_input || jsonb_build_object('identity', jsonb_build_object('channel', coalesce(v_contact_input ->> 'channel', v_inbox.${ib("channel")}), 'external_id', v_contact_input ->> 'external_id'));
  end if;
  select * into v_conv from ${T("conversations")}
  where ${cv("inbox")} = v_inbox.${ib("id")} and ${cv("thread")} = input ->> 'thread_id'
  for update;
  if not found then
    v_contact := ${fn("inbox_resolve_contact")}(v_inbox.${ib("tenant")}, v_contact_input);
    insert into ${T("conversations")} (${cv("tenant")}, ${cv("inbox")}, ${cv("contact")}, ${cv("subject")}, ${cv("botMode")}, ${cv("thread")}, ${cv("metadata")})
    values (v_inbox.${ib("tenant")}, v_inbox.${ib("id")}, v_contact.${ct("id")}, input ->> 'subject', v_inbox.${ib("botMode")}, input ->> 'thread_id', coalesce(input -> 'metadata', '{}'::jsonb))
    returning * into v_conv;
    v_created := true;
    ${log("opened", "jsonb_build_object('by', 'channel')")}
    ${conversationEvent("inbox.conversation.opened", "")}
  end if;
  if v_message ? 'external_id' then
    v_duplicate := exists (select 1 from ${T("messages")} m where m.${ms("conversation")} = v_conv.${cv("id")} and m.${ms("externalId")} = v_message ->> 'external_id');
  end if;
  v_msg := ${fn("inbox_add_message")}(
    v_conv.${cv("id")},
    v_message - 'kind',
    case when coalesce(input ->> 'direction', 'inbound') = 'inbound' then 'contact' else coalesce(input ->> 'author_type', 'bot') end,
    null,
    coalesce(input ->> 'direction', 'inbound')
  );
  return jsonb_build_object(
    'conversation_id', v_conv.${cv("id")},
    'message_id', v_msg.${ms("id")},
    'contact_id', v_conv.${cv("contact")},
    'tenant_id', v_conv.${cv("tenant")},
    'created', v_created,
    'duplicate', v_duplicate
  );
end;
$$;
${serviceOnly(`${fn("record_inbound")}(jsonb)`)}

-- Assigns a conversation to a member (null unassigns) and optionally a team.
-- The assign key assigns anyone; the reply key only takes it for oneself.
create or replace function ${fn("assign_conversation")}(conversation uuid, assignee uuid, team uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_conv ${T("conversations")}%rowtype;
  v_before uuid;${notifyDeclare}
begin
  ${loadConversation("assign_conversation.conversation")}
  if not (${service} or ${staffCan("assign")} or (assignee = (select auth.uid()) and ${staffCan("reply")})) then
    ${forbidden("not allowed to assign this conversation")}
  end if;
  if assignee is not null and not coalesce(better_supabase.can_user(assignee, 'tenant', v_conv.${cv("tenant")}, ${q.key("read")}), false) then
    raise exception 'the assignee cannot read this inbox' using errcode = '22023', hint = 'INBOX_ASSIGNEE_INVALID';
  end if;
  v_before := v_conv.${cv("assignee")};
  update ${T("conversations")} set
    ${cv("assignee")} = assign_conversation.assignee,
    ${cv("team")} = coalesce(assign_conversation.team, ${cv("team")})
  where ${cv("id")} = v_conv.${cv("id")}
  returning * into v_conv;
  if v_before is distinct from assignee then
    ${log("assigned", "jsonb_build_object('from', v_before, 'to', assign_conversation.assignee)")}
    ${conversationEvent("inbox.conversation.assigned", ", 'previousAssigneeId', v_before")}
    if assignee is not null then
      insert into ${T("participants")} (${pa("conversation")}, ${pa("user")}) values (v_conv.${cv("id")}, assignee)
      on conflict do nothing;
    end if;
    if assignee is not null and assignee is distinct from (select auth.uid()) then${notify(`jsonb_build_object(
        'type', 'inbox.assigned',
        'tenant', v_conv.${cv("tenant")},
        'actor', (select auth.uid()),
        'subject_type', 'conversation',
        'subject_id', v_conv.${cv("id")}::text,
        'summary', v_conv.${cv("subject")},
        'recipients', to_jsonb(array[assignee]),
        'key', 'inbox.assigned:' || v_conv.${cv("id")}::text || ':' || assignee::text || ':' || extract(epoch from now())::text,
        'data', jsonb_build_object('conversationId', v_conv.${cv("id")})
      )`)}
      null;
    end if;
  end if;
  return ${conversationJson}(v_conv.${cv("id")});
end;
$$;
${authed(`${fn("assign_conversation")}(uuid, uuid, uuid)`)}

create or replace function ${fn("set_conversation_status")}(conversation uuid, status text, snoozed_until timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_conv ${T("conversations")}%rowtype;
  v_before text;
begin
  ${loadConversation("set_conversation_status.conversation")}
  if not (${service} or ${staffCan("reply")}) then
    ${forbidden("not allowed to change this conversation")}
  end if;
  if status = 'snoozed' and snoozed_until is null then
    raise exception 'snoozing needs snoozed_until' using errcode = '22023', hint = 'INBOX_SNOOZE_UNTIL';
  end if;
  v_before := v_conv.${cv("status")};
  update ${T("conversations")} set
    ${cv("status")} = set_conversation_status.status,
    ${cv("snoozedUntil")} = case when set_conversation_status.status = 'snoozed' then set_conversation_status.snoozed_until end,
    ${cv("resolvedAt")} = case when set_conversation_status.status = 'resolved' then now() end
  where ${cv("id")} = v_conv.${cv("id")}
  returning * into v_conv;
  if v_before is distinct from status then
    ${log("status", "jsonb_build_object('from', v_before, 'to', set_conversation_status.status)")}
    if status = 'resolved' then
      ${conversationEvent("inbox.conversation.resolved", "")}
    elsif v_before = 'resolved' then
      ${conversationEvent("inbox.conversation.reopened", "")}
    end if;
  end if;
  return ${conversationJson}(v_conv.${cv("id")});
end;
$$;
${authed(`${fn("set_conversation_status")}(uuid, text, timestamptz)`)}

-- Sets who answers: bot, human (staff) or paused (nobody, e.g. while the
-- contact is blocked). Going from bot to human is a hand-off: the assignee
-- (or the inbox's members) are told.
create or replace function ${fn("set_bot_mode")}(conversation uuid, mode text, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_conv ${T("conversations")}%rowtype;
  v_before text;${notifyDeclare}
begin
  ${loadConversation("set_bot_mode.conversation")}
  if not (${service} or ${staffCan("reply")}) then
    ${forbidden("not allowed to change this conversation")}
  end if;
  v_before := v_conv.${cv("botMode")};
  update ${T("conversations")} set ${cv("botMode")} = mode where ${cv("id")} = v_conv.${cv("id")} returning * into v_conv;
  if v_before is distinct from mode then
    ${log("handoff", "jsonb_build_object('from', v_before, 'to', set_bot_mode.mode, 'reason', set_bot_mode.reason)")}
    if v_before = 'bot' and mode = 'human' then${notify(`jsonb_build_object(
        'type', 'inbox.handoff',
        'tenant', v_conv.${cv("tenant")},
        'actor', (select auth.uid()),
        'subject_type', 'conversation',
        'subject_id', v_conv.${cv("id")}::text,
        'summary', coalesce(set_bot_mode.reason, v_conv.${cv("preview")}),
        'recipients', ${audience},
        'key', 'inbox.handoff:' || v_conv.${cv("id")}::text || ':' || extract(epoch from now())::text,
        'data', jsonb_build_object('conversationId', v_conv.${cv("id")}, 'reason', set_bot_mode.reason)
      )`)}
      null;
    end if;
  end if;
  return ${conversationJson}(v_conv.${cv("id")});
end;
$$;
${authed(`${fn("set_bot_mode")}(uuid, text, text)`)}

create or replace function ${fn("mark_conversation_read")}(conversation uuid)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_at timestamptz := clock_timestamp();
begin
  if (select auth.uid()) is null or not ${fn("inbox_conversation_allowed")}(conversation::text) then
    ${forbidden("not allowed to read this conversation")}
  end if;
  insert into ${T("reads")} (${rd("conversation")}, ${rd("user")}, ${rd("lastReadAt")})
  values (conversation, (select auth.uid()), v_at)
  on conflict (${rd("conversation")}, ${rd("user")}) do update set ${rd("lastReadAt")} = excluded.${rd("lastReadAt")};
  return v_at;
end;
$$;
${authed(`${fn("mark_conversation_read")}(uuid)`)}

-- Adds or removes the caller's reaction; the service passes actor (a user
-- id, or a name such as the bot's). Returns the message's reactions.
create or replace function ${fn("react_to_message")}(message uuid, emoji text, present boolean default true, actor text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_msg ${T("messages")}%rowtype;
  v_who text;
begin
  select * into v_msg from ${T("messages")} where ${ms("id")} = react_to_message.message for update;
  if not found then
    ${missing("message", "MESSAGE_NOT_FOUND")}
  end if;
  if ${service} then
    v_who := coalesce(actor, 'bot');
  elsif v_msg.${ms("kind")} = 'message' and ${fn("inbox_conversation_allowed")}(v_msg.${ms("conversation")}::text, true) then
    v_who := (select auth.uid())::text;
  elsif v_msg.${ms("kind")} = 'note' and ${q.can(`v_msg.${ms("tenant")}`, "reply")} then
    v_who := (select auth.uid())::text;
  else
    ${forbidden("not allowed to react to this message")}
  end if;
  if length(emoji) not between 1 and 64 then
    raise exception 'emoji must be 1 to 64 characters' using errcode = '22023', hint = 'INBOX_REACTION_INVALID';
  end if;
  update ${T("messages")} set ${ms("reactions")} = case
    when coalesce(present, true) then
      ${ms("reactions")} || jsonb_build_object(emoji, (
        select coalesce(jsonb_agg(distinct x), '[]'::jsonb)
        from jsonb_array_elements_text(coalesce(${ms("reactions")} -> emoji, '[]'::jsonb) || to_jsonb(v_who)) x
      ))
    else
      case when (select count(*) from jsonb_array_elements_text(coalesce(${ms("reactions")} -> emoji, '[]'::jsonb)) x where x <> v_who) = 0
        then ${ms("reactions")} - emoji
        else ${ms("reactions")} || jsonb_build_object(emoji, (select jsonb_agg(x) from jsonb_array_elements_text(${ms("reactions")} -> emoji) x where x <> v_who))
      end
    end
  where ${ms("id")} = v_msg.${ms("id")}
  returning * into v_msg;
  return v_msg.${ms("reactions")};
end;
$$;
${authed(`${fn("react_to_message")}(uuid, text, boolean, text)`)}

-- The author (or the service) edits a message's body, or deletes it: the
-- row stays as a tombstone with an empty body.
create or replace function ${fn("edit_message")}(message uuid, body text default null, remove boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_msg ${T("messages")}%rowtype;
begin
  select * into v_msg from ${T("messages")} where ${ms("id")} = edit_message.message for update;
  if not found then
    ${missing("message", "MESSAGE_NOT_FOUND")}
  end if;
  if not (${service} or (v_msg.${ms("author")} is not null and v_msg.${ms("author")} = (select auth.uid()))) then
    ${forbidden("only the author edits a message")}
  end if;
  if v_msg.${ms("deletedAt")} is not null then
    raise exception 'message is deleted' using errcode = '22023', hint = 'MESSAGE_DELETED';
  end if;
  update ${T("messages")} set
    ${ms("body")} = case when coalesce(remove, false) then '' else coalesce(edit_message.body, ${ms("body")}) end,
    ${ms("attachments")} = case when coalesce(remove, false) then '[]'::jsonb else ${ms("attachments")} end,
    ${ms("deletedAt")} = case when coalesce(remove, false) then now() end,
    ${ms("editedAt")} = case when coalesce(remove, false) then ${ms("editedAt")} else now() end
  where ${ms("id")} = v_msg.${ms("id")}
  returning * into v_msg;
  return to_jsonb(v_msg);
end;
$$;
${authed(`${fn("edit_message")}(uuid, text, boolean)`)}

-- Conversations the caller reads (staff of the tenant, or a contact's own),
-- newest activity first. filter: inbox_id, status ('all' for every status),
-- assignee ('me', 'unassigned' or an id), team_id, contact_id, search,
-- before ({ last_message_at, id } of the previous page's last item), limit.
create or replace function ${fn("list_conversations")}(tenant ${id} default null, filter jsonb default '{}'::jsonb)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(${conversationJson}(page.${cv("id")}) || jsonb_build_object('unread', page.unread) order by page.${cv("lastMessageAt")} desc, page.${cv("id")} desc), '[]'::jsonb)
  from (
    select v.${cv("id")}, v.${cv("lastMessageAt")},
      v.${cv("lastMessageAt")} > coalesce((select r.${rd("lastReadAt")} from ${T("reads")} r where r.${rd("conversation")} = v.${cv("id")} and r.${rd("user")} = (select auth.uid())), '-infinity'::timestamptz) as unread
    from ${T("conversations")} v
    left join ${T("contacts")} c on c.${ct("id")} = v.${cv("contact")}
    where (list_conversations.tenant is null or v.${cv("tenant")} = list_conversations.tenant)
      and (filter ->> 'inbox_id' is null or v.${cv("inbox")} = (filter ->> 'inbox_id')::uuid)
      and (coalesce(filter ->> 'status', 'open') = 'all' or v.${cv("status")} = coalesce(filter ->> 'status', 'open'))
      and (case filter ->> 'assignee'
        when 'me' then v.${cv("assignee")} = (select auth.uid())
        when 'unassigned' then v.${cv("assignee")} is null
        else filter ->> 'assignee' is null or v.${cv("assignee")} = (filter ->> 'assignee')::uuid end)
      and (filter ->> 'team_id' is null or v.${cv("team")} = (filter ->> 'team_id')::uuid)
      and (filter ->> 'contact_id' is null or v.${cv("contact")} = (filter ->> 'contact_id')::uuid)
      and (nullif(filter ->> 'search', '') is null
        or v.${cv("subject")} ilike '%' || (filter ->> 'search') || '%'
        or v.${cv("preview")} ilike '%' || (filter ->> 'search') || '%'
        or c.${ct("name")} ilike '%' || (filter ->> 'search') || '%'
        or c.${ct("email")} ilike '%' || (filter ->> 'search') || '%')
      and (filter -> 'before' is null
        or (v.${cv("lastMessageAt")}, v.${cv("id")}) < ((filter -> 'before' ->> 'last_message_at')::timestamptz, (filter -> 'before' ->> 'id')::uuid))
    order by v.${cv("lastMessageAt")} desc, v.${cv("id")} desc
    limit least(greatest(coalesce((filter ->> 'limit')::integer, 50), 1), 200)
  ) page;
$$;
${authed(`${fn("list_conversations")}(${id}, jsonb)`)}

create or replace function ${fn("get_conversation")}(conversation uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select ${conversationJson}(v.${cv("id")}) from ${T("conversations")} v where v.${cv("id")} = conversation;
$$;
${authed(`${fn("get_conversation")}(uuid)`)}

-- A page of messages, oldest first, ending before the given instant. Staff
-- also get notes and each outbound message's delivery.
create or replace function ${fn("list_messages")}(conversation uuid, before timestamptz default null, max integer default 50)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(page.item order by page.created_at, page.id), '[]'::jsonb)
  from (
    select m.${ms("createdAt")} as created_at, m.${ms("id")} as id,
      to_jsonb(m) || jsonb_build_object('delivery', (
        select jsonb_build_object('status', d.${dl("status")}, 'channel', d.${dl("channel")}, 'error', d.${dl("error")}, 'updated_at', d.${dl("updatedAt")})
        from ${T("deliveries")} d where d.${dl("message")} = m.${ms("id")}
        order by d.${dl("createdAt")} limit 1
      )) as item
    from ${T("messages")} m
    where m.${ms("conversation")} = list_messages.conversation
      and (before is null or m.${ms("createdAt")} < before)
    order by m.${ms("createdAt")} desc, m.${ms("id")} desc
    limit least(greatest(coalesce(max, 50), 1), 200)
  ) page;
$$;
${authed(`${fn("list_messages")}(uuid, timestamptz, integer)`)}

-- The conversation's activity log, for staff.
create or replace function ${fn("list_conversation_events")}(conversation uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(e) order by e.${ev("id")}), '[]'::jsonb)
  from ${T("events")} e where e.${ev("conversation")} = list_conversation_events.conversation;
$$;
${authed(`${fn("list_conversation_events")}(uuid)`)}

-- Counts of open conversations for the caller: all, assigned to them,
-- unassigned, and those with activity since they last read them.
create or replace function ${fn("inbox_counts")}(tenant ${id})
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'open', count(*),
    'mine', count(*) filter (where v.${cv("assignee")} = (select auth.uid())),
    'unassigned', count(*) filter (where v.${cv("assignee")} is null),
    'unread', count(*) filter (where v.${cv("lastMessageAt")} > coalesce(r.${rd("lastReadAt")}, '-infinity'::timestamptz)
      and (v.${cv("assignee")} is null or v.${cv("assignee")} = (select auth.uid())))
  )
  from ${T("conversations")} v
  left join ${T("reads")} r on r.${rd("conversation")} = v.${cv("id")} and r.${rd("user")} = (select auth.uid())
  where v.${cv("tenant")} = inbox_counts.tenant and v.${cv("status")} = 'open';
$$;
${authed(`${fn("inbox_counts")}(${id})`)}`;
}
