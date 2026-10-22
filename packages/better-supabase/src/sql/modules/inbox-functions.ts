import type { InboxCommand, InboxSql } from "./inbox-names.ts";

import { sqlString } from "../../core/template.ts";
import { serviceGrant, fail } from "../shared.ts";
import { forbidden, missing } from "./inbox-names.ts";
import { inboxReactFunction, inboxReadFunctions } from "./inbox-reads.ts";

/** The SQL functions: the writes and the reads with joined rows. */
export function inboxFunctions(
  q: InboxSql,
  teamFns?: {
    readonly create: string;
    readonly add: string;
    readonly remove: string;
  },
): string {
  const { id, fn } = q;
  const ib = q.cols("inboxes");
  const mb = q.cols("members");
  const tm = q.cols("teams");
  const tmm = q.cols("teamMembers");
  const ct = q.cols("contacts");
  const ci = q.cols("identities");
  const cv = q.cols("conversations");
  const ev = q.cols("events");
  const dt = q.cols("details");
  const dl = q.cols("deliveries");
  const T = (name: string): string => q.t(name);
  const service = q.service;
  const core = q.core;
  const cm = core.cols("messages");
  const cc = core.cols("conversations");
  const ck = core.cols("members");
  const at = q.ctx.of("attachments");
  const a = (column: string): string => at.col("attachments", column);

  const authed = (signature: string): string =>
    `revoke execute on function ${signature} from public, anon;
grant execute on function ${signature} to authenticated, service_role;`;

  const internal = (signature: string): string =>
    `revoke execute on function ${signature} from public, anon, authenticated;`;

  const ctx = q.ctx;

  // Someone who writes, is assigned or reads joins the core conversation, so
  // its member row holds their read marker.
  const join = (conversation: string, tenant: string, user: string): string =>
    `insert into ${core.t("members")} (${ck("conversation")}, ${ck("tenant")}, ${ck("user")})
    values (${conversation}, ${tenant}, ${user})
    on conflict do nothing;`;

  const notifyOn = ctx.installed("notifications") && ctx.flag("notify", true);

  const notify = (fields: string): string =>
    notifyOn
      ? `
  ${ctx.notify(fields)}`
      : "";

  const notifyDeclare = notifyOn ? "\n  v_claims text;" : "";

  const enqueue = (queue: string, payload: string, dedupe: string): string =>
    ctx.enqueue(queue, payload, dedupe);

  const conversationEvent = (type: string, extra: string): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('conversationId', v_conv.${cv("id")}, 'organizationId', v_conv.${cv("tenant")}::text, 'inboxId', v_conv.${cv("inbox")}, 'contactId', v_conv.${cv("contact")}, 'assigneeId', v_conv.${cv("assignee")}, 'status', v_conv.${cv("status")}${extra})`,
      subject: `'conversations/' || v_conv.${cv("id")}::text`,
      tenant: `v_conv.${cv("tenant")}`,
      audit: false,
    });

  const received = ctx.record({
    type: "inbox_message.received",
    payload: `jsonb_build_object('conversationId', v_conv.${cv("id")}, 'organizationId', v_conv.${cv("tenant")}::text, 'messageId', v_id, 'inboxId', v_conv.${cv("inbox")}, 'contactId', v_conv.${cv("contact")})`,
    subject: `'conversations/' || v_conv.${cv("id")}::text`,
    tenant: `v_conv.${cv("tenant")}`,
    key: `'inbox_message.received:' || v_id::text`,
    audit: false,
  });

  const log = (type: string, data = "'{}'::jsonb"): string =>
    `insert into ${T("events")} (${ev("tenant")}, ${ev("conversation")}, ${ev("type")}, ${ev("actor")}, ${ev("data")})
  values (v_conv.${cv("tenant")}, v_conv.${cv("id")}, ${sqlString(type)}, (select auth.uid()), ${data});`;

  // Who to tell about the conversation: the assignee, or the inbox's members
  // while nobody is assigned.
  const audience = `case when v_conv.${cv("assignee")} is not null then to_jsonb(array[v_conv.${cv("assignee")}])
    else coalesce((select jsonb_agg(m.${mb("user")}) from ${T("members")} m where m.${mb("inbox")} = v_conv.${cv("inbox")}), '[]'::jsonb) end`;

  const conversationJson = fn("inbox_conversation_json");
  const messagesJson = fn("inbox_messages_json");

  const staffCan = (action: "read" | "reply" | "assign" | "manage"): string =>
    q.can(`v_conv.${cv("tenant")}`, action);

  const command = (
    name: InboxCommand,
    action: "read" | "reply" | "assign" | "manage",
  ): string => q.command(`v_conv.${cv("tenant")}`, name, action);

  const loadConversation = (
    param: string,
  ): string => `select * into v_conv from ${T("conversations")} where ${cv("id")} = ${param} for update;
  if not found then
    ${missing("conversation", "CONVERSATION_NOT_FOUND")}
  end if;`;

  // A new conversation is a core conversation of kind inbox and the inbox row
  // with the same id. v_id holds the new id.
  const openCore = (tenant: string): string =>
    `v_id := gen_random_uuid();
  insert into ${core.t("conversations")} (${cc("id")}, ${cc("tenant")}, ${cc("kind")}, ${cc("access")}, ${cc("createdBy")})
  values (v_id, ${tenant}, 'inbox', 'tenant', (select auth.uid()));`;

  const ready = `to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null`;

  const tooLong = (body: string): string =>
    `if length(${body}) > ${String(q.maxBody)} then
    ${fail("INBOX_MESSAGE_TOO_LONG", `a message is at most ${String(q.maxBody)} characters`, "22023")}
  end if;`;

  return `-- When the contact last read the conversation, for staff read receipts.
create or replace function ${fn("inbox_contact_read_at")}(conversation uuid)
returns timestamptz
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return (
    select k.${ck("lastReadAt")}
    from ${T("conversations")} v
    join ${T("contacts")} c on c.${ct("id")} = v.${cv("contact")}
    join ${core.t("members")} k on k.${ck("conversation")} = v.${cv("id")} and k.${ck("user")} = c.${ct("user")}
    where v.${cv("id")} = inbox_contact_read_at.conversation
      and (${service} or ${q.can(`v.${cv("tenant")}`, "read")})
  );
end;
$$;
${authed(`${fn("inbox_contact_read_at")}(uuid)`)}

-- A conversation with its contact and inbox, as the reads return it.
create or replace function ${conversationJson}(conversation uuid)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
begin
  return (
    select to_jsonb(v) || jsonb_build_object(
      'contact', (select jsonb_build_object('id', c.${ct("id")}, 'name', c.${ct("name")}, 'email', c.${ct("email")}, 'phone', c.${ct("phone")}, 'avatar_url', c.${ct("avatarUrl")}, 'user_id', c.${ct("user")}) from ${T("contacts")} c where c.${ct("id")} = v.${cv("contact")}),
      'inbox', (select jsonb_build_object('id', i.${ib("id")}, 'name', i.${ib("name")}, 'channel', i.${ib("channel")}) from ${T("inboxes")} i where i.${ib("id")} = v.${cv("inbox")}),
      'last_read_at', (select k.${ck("lastReadAt")} from ${core.t("members")} k where k.${ck("conversation")} = v.${cv("id")} and k.${ck("user")} = (select auth.uid())),
      'contact_read_at', ${fn("inbox_contact_read_at")}(v.${cv("id")})
    )
    from ${T("conversations")} v
    where v.${cv("id")} = inbox_conversation_json.conversation
  );
end;
$$;
${authed(`${conversationJson}(uuid)`)}

-- Messages of ids the caller reads, oldest first, as the messaging core
-- returns them (author, files and reactions included) with the inbox's own
-- fields. Staff also get notes and each outbound message's delivery. It runs
-- as its owner so a contact sees the files and reactions of their messages.
create or replace function ${messagesJson}(ids uuid[])
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_ids uuid[];
begin
  select array_agg(m.${cm("id")}) into v_ids
  from ${core.t("messages")} m
  join ${T("details")} d on d.${dt("message")} = m.${cm("id")}
  where m.${cm("id")} = any (inbox_messages_json.ids)
    and m.${cm("sentAt")} is not null
    and ${fn("inbox_conversation_allowed")}(d.${dt("conversation")}::text)
    and (m.${cm("kind")} = 'message' or ${fn("inbox_note_readable")}(d.${dt("conversation")}));
  if v_ids is null then
    return '[]'::jsonb;
  end if;
  return (
    select coalesce(jsonb_agg(x.item || to_jsonb(d) || jsonb_build_object('delivery', case when ${fn("inbox_note_readable")}(d.${dt("conversation")}) then (
      select jsonb_build_object('status', l.${dl("status")}, 'channel', l.${dl("channel")}, 'error', l.${dl("error")}, 'updated_at', l.${dl("updatedAt")})
      from ${T("deliveries")} l where l.${dl("message")} = d.${dt("message")}
      order by l.${dl("createdAt")} limit 1
    ) end) order by x.n), '[]'::jsonb)
    from jsonb_array_elements(${core.fn("messaging_messages_json")}(v_ids)) with ordinality as x (item, n)
    join ${T("details")} d on d.${dt("message")} = (x.item ->> ${sqlString(cm("id").replaceAll('"', ""))})::uuid
  );
end;
$$;
${authed(`${messagesJson}(uuid[])`)}

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
  if not ${ctx.scope.canUser("member", "v_tenant", q.key("read"))} then
    ${fail("INBOX_MEMBER_INVALID", "user cannot read this inbox", "22023")}
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
begin
  if not (${service} or ${q.can("create_inbox_team.tenant", "manage")}) then
    ${forbidden("not allowed to manage inboxes")}
  end if;
  ${
    teamFns
      ? `return ${teamFns.create}(create_inbox_team.tenant, create_inbox_team.name, null);`
      : `declare
    v_row ${T("teams")}%rowtype;
  begin
    insert into ${T("teams")} (${tm("tenant")}, ${tm("name")}) values (create_inbox_team.tenant, create_inbox_team.name)
    returning * into v_row;
    return to_jsonb(v_row);
  end;`
  }
end;
$$;
${authed(`${fn("create_inbox_team")}(${id}, text)`)}

create or replace function ${fn("set_inbox_team_member")}(team uuid, member uuid, present boolean default true)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
${
  teamFns
    ? `begin
  if not coalesce(present, true) then
    return ${teamFns.remove}(set_inbox_team_member.team, member);
  end if;
  return ${teamFns.add}(set_inbox_team_member.team, member);
end;`
    : `declare
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
end;`
}
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

-- Stores a message on a conversation as a core message with its inbox
-- fields, and moves the conversation along: the preview, the first response,
-- a reopen when the contact writes, the files, the bot job, the outbound job
-- and the notifications. input.attachments are ids of the author's uploads
-- to the conversation; input.files ({ url, name, content_type, size }) are a
-- channel's files, stored as pending attachments the service imports.
-- Callers check access. Returns the message id.
create or replace function ${fn("inbox_add_message")}(conversation uuid, input jsonb, author_type text, author uuid, direction text)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_conv ${T("conversations")}%rowtype;
  v_inbox ${T("inboxes")}%rowtype;
  v_id uuid;
  v_at timestamptz := clock_timestamp();
  v_kind text := coalesce(input ->> 'kind', 'message');
  v_body text := coalesce(input ->> 'body', '');
  v_mentions uuid[];
  v_uploads uuid[];
  v_file jsonb;
  v_moved integer;
  v_reopened boolean := false;${notifyDeclare}
begin
  select * into v_conv from ${T("conversations")} where ${cv("id")} = inbox_add_message.conversation for update;
  select * into v_inbox from ${T("inboxes")} where ${ib("id")} = v_conv.${cv("inbox")};
  if input ? 'external_id' then
    select d.${dt("message")} into v_id from ${T("details")} d
    where d.${dt("conversation")} = v_conv.${cv("id")} and d.${dt("externalId")} = input ->> 'external_id';
    if found then
      return v_id;
    end if;
  end if;
  if v_kind not in ('message', 'note') then
    ${fail("INBOX_KIND_INVALID", "kind is message or note", "22023")}
  end if;
  v_uploads := array(select distinct x::uuid from jsonb_array_elements_text(coalesce(input -> 'attachments', '[]'::jsonb)) x);
  if length(btrim(v_body)) = 0 and cardinality(v_uploads) = 0 and coalesce(jsonb_array_length(input -> 'files'), 0) = 0 then
    ${fail("INBOX_MESSAGE_EMPTY", "a message needs a body or an attachment", "22023")}
  end if;
  ${tooLong("v_body")}
  select coalesce(array_agg(distinct x), '{}') into v_mentions
  from jsonb_array_elements_text(coalesce(input -> 'mentions', '[]'::jsonb)) e(raw)
  cross join lateral (select e.raw::uuid as x) u
  where ${ctx.scope.canUser("u.x", `v_conv.${cv("tenant")}`, q.key("read"))};
  insert into ${core.t("messages")} (${cm("tenant")}, ${cm("conversation")}, ${cm("author")}, ${cm("kind")}, ${cm("body")}, ${cm("mentions")}, ${cm("sentAt")}, ${cm("createdAt")})
  values (v_conv.${cv("tenant")}, v_conv.${cv("id")}, inbox_add_message.author, v_kind, v_body, v_mentions, v_at, v_at)
  returning ${cm("id")} into v_id;
  perform ${core.fn("index_record_mentions")}(v_id);
  insert into ${T("details")} (${dt("message")}, ${dt("tenant")}, ${dt("conversation")}, ${dt("direction")}, ${dt("authorType")}, ${dt("format")}, ${dt("externalId")}, ${dt("replyTo")}, ${dt("metadata")})
  values (
    v_id, v_conv.${cv("tenant")}, v_conv.${cv("id")}, inbox_add_message.direction, inbox_add_message.author_type,
    coalesce(input ->> 'format', 'text'), input ->> 'external_id', (input ->> 'reply_to')::uuid, coalesce(input -> 'metadata', '{}'::jsonb)
  );
  if cardinality(v_uploads) > 0 then
    update ${at.table("attachments")} x set ${a("subjectType")} = ${core.message}, ${a("subjectId")} = v_id::text
    where x.${a("id")} = any (v_uploads)
      and x.${a("tenant")} = v_conv.${cv("tenant")}
      and x.${a("subjectType")} = ${core.conversation} and x.${a("subjectId")} = v_conv.${cv("id")}::text
      and x.${a("status")} <> 'infected'
      and (inbox_add_message.author is null or x.${a("uploadedBy")} = inbox_add_message.author);
    get diagnostics v_moved = row_count;
    if v_moved <> cardinality(v_uploads) then
      ${fail("INBOX_ATTACHMENT_INVALID", "attachments must be your uploads to this conversation", "22023")}
    end if;
  end if;
  for v_file in select f from jsonb_array_elements(coalesce(input -> 'files', '[]'::jsonb)) f loop
    insert into ${at.table("attachments")} (${a("tenant")}, ${a("subjectType")}, ${a("subjectId")}, ${a("name")}, ${a("mimeType")}, ${a("size")}, ${a("uploadedBy")}, ${a("detail")})
    values (
      v_conv.${cv("tenant")}, ${core.message}, v_id::text,
      left(coalesce(nullif(v_file ->> 'name', ''), 'file'), 255),
      lower(coalesce(nullif(v_file ->> 'content_type', ''), 'application/octet-stream')),
      coalesce((v_file ->> 'size')::bigint, 0),
      null,
      jsonb_build_object('source', v_file)::text
    );
  end loop;
  if inbox_add_message.author is not null then
    ${join(`v_conv.${cv("id")}`, `v_conv.${cv("tenant")}`, "inbox_add_message.author")}
  end if;
  if v_kind = 'message' then
    v_reopened := inbox_add_message.direction = 'inbound' and v_conv.${cv("status")} in ('resolved', 'snoozed');
    update ${T("conversations")} set
      ${cv("lastMessageAt")} = v_at,
      ${cv("preview")} = left(v_body, 140),
      ${cv("firstResponseAt")} = case
        when ${cv("firstResponseAt")} is null and inbox_add_message.direction = 'outbound' and inbox_add_message.author_type in ('agent', 'bot') then v_at
        else ${cv("firstResponseAt")} end,
      ${cv("status")} = case when v_reopened then 'open' else ${cv("status")} end,
      ${cv("snoozedUntil")} = case when v_reopened then null else ${cv("snoozedUntil")} end,
      ${cv("resolvedAt")} = case when v_reopened then null else ${cv("resolvedAt")} end
    where ${cv("id")} = v_conv.${cv("id")}
    returning * into v_conv;
    if v_reopened then
      ${log("reopened", "jsonb_build_object('by', 'contact')")}
      ${conversationEvent("inbox_conversation.reopened", "")}
    end if;
  end if;
  if v_kind = 'message' and inbox_add_message.direction = 'inbound' then
    ${received}
    if v_conv.${cv("botMode")} = 'bot' then
      ${enqueue(q.botQueue, `jsonb_build_object('conversation_id', v_conv.${cv("id")}, 'message_id', v_id, 'thread_id', v_conv.${cv("thread")}, 'inbox_id', v_conv.${cv("inbox")})`, `'inbox:' || v_conv.${cv("id")}::text`)}
    end if;${notify(`jsonb_build_object(
      'type', 'inbox.message',
      'tenant', v_conv.${cv("tenant")},
      'subject_type', 'conversation',
      'subject_id', v_conv.${cv("id")}::text,
      'summary', left(v_body, 140),
      'recipients', ${audience},
      'key', 'inbox.message:' || v_id::text,
      'data', jsonb_build_object('conversationId', v_conv.${cv("id")}, 'messageId', v_id)
    )`)}
  end if;
  if v_kind = 'message' and inbox_add_message.direction = 'outbound' and v_inbox.${ib("channel")} <> 'in_app' then
    insert into ${T("deliveries")} (${dl("tenant")}, ${dl("message")}, ${dl("channel")})
    values (v_conv.${cv("tenant")}, v_id, v_inbox.${ib("channel")})
    on conflict do nothing;
    if not coalesce((input ->> 'delivered_by_caller')::boolean, false) then
      ${enqueue(q.outboundQueue, `jsonb_build_object('message_id', v_id, 'conversation_id', v_conv.${cv("id")}, 'inbox_id', v_conv.${cv("inbox")})`, `'inbox-out:' || v_id::text`)}
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
      'summary', left(v_body, 140),
      'recipients', to_jsonb(v_mentions),
      'key', 'inbox.mention:' || v_id::text,
      'data', jsonb_build_object('conversationId', v_conv.${cv("id")}, 'messageId', v_id)
    )`)}
  end if;`
      : ""
  }
  return v_id;
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
  v_id uuid;
  v_staff boolean;
  v_contact_input jsonb := coalesce(input -> 'contact', '{}'::jsonb);
begin
  select * into v_inbox from ${T("inboxes")} where ${ib("id")} = start_conversation.inbox and ${ib("archivedAt")} is null;
  if not found then
    ${missing("inbox", "INBOX_NOT_FOUND")}
  end if;
  -- A signed-in caller who names no contact on a widget inbox is the
  -- visitor, staff included, so they can try their own widget.
  if not ${service} and (select auth.uid()) is not null and not (input ? 'contact')
    and v_inbox.${ib("channel")} = 'in_app' and coalesce((v_inbox.${ib("settings")} ->> 'widget')::boolean, false) then
    v_staff := false;
    v_contact_input := jsonb_build_object(
      'user_id', (select auth.uid()),
      'name', v_contact_input ->> 'name',
      'email', coalesce((select auth.jwt()) ->> 'email', v_contact_input ->> 'email')
    );
  elsif ${service} or ${q.can(`v_inbox.${ib("tenant")}`, "reply")} then
    v_staff := true;
    if jsonb_typeof(input -> 'contact') = 'string' then
      v_contact_input := jsonb_build_object('id', input ->> 'contact');
    end if;
    if v_contact_input = '{}'::jsonb then
      ${fail("CONTACT_REQUIRED", "input.contact is required", "22023")}
    end if;
  else
    ${forbidden("not allowed to open a conversation in this inbox")}
  end if;
  v_contact := ${fn("inbox_resolve_contact")}(v_inbox.${ib("tenant")}, v_contact_input);
  ${openCore(`v_inbox.${ib("tenant")}`)}
  insert into ${T("conversations")} (${cv("id")}, ${cv("tenant")}, ${cv("inbox")}, ${cv("contact")}, ${cv("subject")}, ${cv("priority")}, ${cv("botMode")}, ${cv("thread")}, ${cv("assignee")}, ${cv("metadata")})
  values (
    v_id, v_inbox.${ib("tenant")}, v_inbox.${ib("id")}, v_contact.${ct("id")}, input ->> 'subject', coalesce(input ->> 'priority', 'normal'),
    coalesce(input ->> 'bot_mode', v_inbox.${ib("botMode")}), coalesce(input ->> 'thread_id', ${sqlString(`${q.topic}:`)} || v_id::text),
    case when v_staff then (input ->> 'assignee_id')::uuid end, coalesce(input -> 'metadata', '{}'::jsonb)
  )
  returning * into v_conv;
  if v_contact.${ct("user")} is not null then
    ${join("v_id", `v_inbox.${ib("tenant")}`, `v_contact.${ct("user")}`)}
  end if;
  if v_conv.${cv("assignee")} is not null then
    ${join("v_id", `v_inbox.${ib("tenant")}`, `v_conv.${cv("assignee")}`)}
  end if;
  ${log("opened")}
  ${conversationEvent("inbox_conversation.opened", "")}
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
-- over to staff. Returns the message as list_inbox_messages does.
create or replace function ${fn("send_inbox_message")}(conversation uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_conv ${T("conversations")}%rowtype;
  v_id uuid;
  v_author_type text;
  v_direction text;
  v_kind text := coalesce(input ->> 'kind', 'message');
begin
  ${loadConversation("send_inbox_message.conversation")}
  if ${service} then
    v_author_type := coalesce(input ->> 'author_type', 'bot');
    v_direction := case when v_author_type = 'contact' then 'inbound' else 'outbound' end;
  elsif exists (select 1 from ${T("contacts")} c where c.${ct("id")} = v_conv.${cv("contact")} and c.${ct("user")} = (select auth.uid())) then
    -- The conversation's own contact writes as the contact, staff included.
    if v_kind <> 'message' then
      ${forbidden("contacts cannot write notes")}
    end if;
    if input ? 'files' then
      ${forbidden("contacts attach their own uploads")}
    end if;
    v_author_type := 'contact';
    v_direction := 'inbound';
  elsif ${command("reply", "reply")} then
    v_author_type := 'agent';
    v_direction := 'outbound';
  else
    ${forbidden("not allowed to write in this conversation")}
  end if;
  v_id := ${fn("inbox_add_message")}(v_conv.${cv("id")}, coalesce(input, '{}'::jsonb) - 'author_type', v_author_type, (select auth.uid()), v_direction);
  if v_author_type = 'agent' and v_kind = 'message' and v_conv.${cv("botMode")} = 'bot' then
    update ${T("conversations")} set ${cv("botMode")} = 'human' where ${cv("id")} = v_conv.${cv("id")} returning * into v_conv;
    ${log("handoff", "jsonb_build_object('from', 'bot', 'to', 'human', 'reason', 'agent_reply')")}
  end if;
  return ${messagesJson}(array[v_id]) -> 0;
end;
$$;
${authed(`${fn("send_inbox_message")}(uuid, jsonb)`)}

-- A pending attachment on the conversation for the caller to upload to:
-- staff who reply, or the conversation's contact. Upload the file to its
-- bucket and object_path, call confirm_attachment, then pass its id in
-- send_inbox_message's input.attachments.
create or replace function ${fn("create_inbox_attachment")}(conversation uuid, name text, mime_type text, size bigint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_conv ${T("conversations")}%rowtype;
  v_row ${at.table("attachments")}%rowtype;
begin
  select * into v_conv from ${T("conversations")} v where v.${cv("id")} = create_inbox_attachment.conversation;
  if not found or (select auth.uid()) is null or not ${fn("inbox_conversation_allowed")}(v_conv.${cv("id")}::text, true) then
    ${forbidden("not allowed to write in this conversation")}
  end if;
  insert into ${at.table("attachments")} (${a("tenant")}, ${a("subjectType")}, ${a("subjectId")}, ${a("name")}, ${a("mimeType")}, ${a("size")}, ${a("uploadedBy")})
  values (v_conv.${cv("tenant")}, ${core.conversation}, v_conv.${cv("id")}::text, create_inbox_attachment.name, lower(create_inbox_attachment.mime_type), create_inbox_attachment.size, (select auth.uid()))
  returning * into v_row;
  return to_jsonb(v_row);
exception when check_violation then
  ${fail("INBOX_ATTACHMENT_INVALID", "the file's name, type or size is not allowed", "22023")}
end;
$$;
${authed(`${fn("create_inbox_attachment")}(uuid, text, text, bigint)`)}

-- A message that arrived on a channel, for the inbound handler: finds the
-- inbox's conversation for the thread (reopening it) or opens one, resolves
-- the contact by its identity on the channel, and stores the message once
-- per external_id. message.files are stored as pending attachments. Returns
-- { conversation_id, message_id, contact_id, created, duplicate }.
create or replace function ${fn("record_inbound")}(input jsonb)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_inbox ${T("inboxes")}%rowtype;
  v_contact ${T("contacts")}%rowtype;
  v_conv ${T("conversations")}%rowtype;
  v_id uuid;
  v_message uuid;
  v_created boolean := false;
  v_duplicate boolean := false;
  v_input jsonb := coalesce(input -> 'message', '{}'::jsonb);
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
    ${openCore(`v_inbox.${ib("tenant")}`)}
    insert into ${T("conversations")} (${cv("id")}, ${cv("tenant")}, ${cv("inbox")}, ${cv("contact")}, ${cv("subject")}, ${cv("botMode")}, ${cv("thread")}, ${cv("metadata")})
    values (v_id, v_inbox.${ib("tenant")}, v_inbox.${ib("id")}, v_contact.${ct("id")}, input ->> 'subject', v_inbox.${ib("botMode")}, input ->> 'thread_id', coalesce(input -> 'metadata', '{}'::jsonb))
    returning * into v_conv;
    if v_contact.${ct("user")} is not null then
      ${join("v_id", `v_inbox.${ib("tenant")}`, `v_contact.${ct("user")}`)}
    end if;
    v_created := true;
    ${log("opened", "jsonb_build_object('by', 'channel')")}
    ${conversationEvent("inbox_conversation.opened", "")}
  end if;
  if v_input ? 'external_id' then
    v_duplicate := exists (select 1 from ${T("details")} d where d.${dt("conversation")} = v_conv.${cv("id")} and d.${dt("externalId")} = v_input ->> 'external_id');
  end if;
  v_message := ${fn("inbox_add_message")}(
    v_conv.${cv("id")},
    v_input - 'kind' - 'attachments',
    case when coalesce(input ->> 'direction', 'inbound') = 'inbound' then 'contact' else coalesce(input ->> 'author_type', 'bot') end,
    null,
    coalesce(input ->> 'direction', 'inbound')
  );
  return jsonb_build_object(
    'conversation_id', v_conv.${cv("id")},
    'message_id', v_message,
    'contact_id', v_conv.${cv("contact")},
    'tenant_id', v_conv.${cv("tenant")},
    'created', v_created,
    'duplicate', v_duplicate
  );
end;
$$;
${serviceGrant(`${fn("record_inbound")}(jsonb)`)}

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
  if not (${service} or ${command("assign", "assign")} or (assignee = (select auth.uid()) and ${staffCan("reply")})) then
    ${forbidden("not allowed to assign this conversation")}
  end if;
  if assignee is not null and not ${ctx.scope.canUser("assignee", `v_conv.${cv("tenant")}`, q.key("read"))} then
    ${fail("INBOX_ASSIGNEE_INVALID", "the assignee cannot read this inbox", "22023")}
  end if;
  v_before := v_conv.${cv("assignee")};
  update ${T("conversations")} set
    ${cv("assignee")} = assign_conversation.assignee,
    ${cv("team")} = coalesce(assign_conversation.team, ${cv("team")})
  where ${cv("id")} = v_conv.${cv("id")}
  returning * into v_conv;
  if v_before is distinct from assignee then
    ${log("assigned", "jsonb_build_object('from', v_before, 'to', assign_conversation.assignee)")}
    ${conversationEvent("inbox_conversation.assigned", ", 'previousAssigneeId', v_before")}
    if assignee is not null then
      ${join(`v_conv.${cv("id")}`, `v_conv.${cv("tenant")}`, "assign_conversation.assignee")}
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
  if not (${service} or ${command("set_status", "reply")}) then
    ${forbidden("not allowed to change this conversation")}
  end if;
  if status = 'snoozed' and snoozed_until is null then
    ${fail("INBOX_SNOOZE_UNTIL", "snoozing needs snoozed_until", "22023")}
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
      ${conversationEvent("inbox_conversation.resolved", "")}
    elsif v_before = 'resolved' then
      ${conversationEvent("inbox_conversation.reopened", "")}
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
  if not (${service} or ${command("set_bot_mode", "reply")}) then
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

-- Marks the conversation read for the caller on their core member row. A
-- contact's read pings the conversation topic, for staff read receipts.
create or replace function ${fn("mark_conversation_read")}(conversation uuid)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_at timestamptz := clock_timestamp();
  v_conv ${T("conversations")}%rowtype;
begin
  if (select auth.uid()) is null or not ${fn("inbox_conversation_allowed")}(conversation::text) then
    ${forbidden("not allowed to read this conversation")}
  end if;
  select * into v_conv from ${T("conversations")} v where v.${cv("id")} = mark_conversation_read.conversation;
  insert into ${core.t("members")} as k (${ck("conversation")}, ${ck("tenant")}, ${ck("user")}, ${ck("lastReadAt")})
  values (v_conv.${cv("id")}, v_conv.${cv("tenant")}, (select auth.uid()), v_at)
  on conflict (${ck("conversation")}, ${ck("user")}) do update set ${ck("lastReadAt")} = greatest(coalesce(k.${ck("lastReadAt")}, excluded.${ck("lastReadAt")}), excluded.${ck("lastReadAt")});
  if ${ready} and exists (select 1 from ${T("contacts")} c where c.${ct("id")} = v_conv.${cv("contact")} and c.${ct("user")} = (select auth.uid())) then
    perform realtime.send(jsonb_build_object('conversation_id', v_conv.${cv("id")}), 'read', ${core.topic(`v_conv.${cv("id")}`)}, true);
  end if;
  return v_at;
end;
$$;
${authed(`${fn("mark_conversation_read")}(uuid)`)}

${inboxReactFunction(q)}

-- The author (or the service) edits a message's body, or deletes it: the
-- message stays as a tombstone with an empty body and its files go.
create or replace function ${fn("edit_inbox_message")}(message uuid, body text default null, remove boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_msg ${core.t("messages")}%rowtype;
begin
  select m.* into v_msg from ${core.t("messages")} m
  join ${T("details")} d on d.${dt("message")} = m.${cm("id")}
  where m.${cm("id")} = edit_inbox_message.message
  for update of m;
  if not found then
    ${missing("message", "MESSAGE_NOT_FOUND")}
  end if;
  if not (${service} or (v_msg.${cm("author")} is not null and v_msg.${cm("author")} = (select auth.uid()))) then
    ${forbidden("only the author edits a message")}
  end if;
  if v_msg.${cm("deletedAt")} is not null then
    ${fail("MESSAGE_DELETED", "message is deleted", "22023")}
  end if;
  ${tooLong("coalesce(edit_inbox_message.body, '')")}
  update ${core.t("messages")} set
    ${cm("body")} = case when coalesce(remove, false) then '' else coalesce(edit_inbox_message.body, ${cm("body")}) end,
    ${cm("deletedAt")} = case when coalesce(remove, false) then now() end,
    ${cm("editedAt")} = case when coalesce(remove, false) then ${cm("editedAt")} else now() end
  where ${cm("id")} = v_msg.${cm("id")};
  perform ${core.fn("index_record_mentions")}(v_msg.${cm("id")});
  if coalesce(remove, false) then
    delete from ${at.table("attachments")} x where x.${a("subjectType")} = ${core.message} and x.${a("subjectId")} = v_msg.${cm("id")}::text;
  end if;
  return ${messagesJson}(array[v_msg.${cm("id")}]) -> 0;
end;
$$;
${authed(`${fn("edit_inbox_message")}(uuid, text, boolean)`)}

${inboxReadFunctions(q)}`;
}
