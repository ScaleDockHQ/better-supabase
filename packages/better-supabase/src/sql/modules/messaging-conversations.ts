import type { MessagingSql } from "./messaging-names.ts";

import { sqlString } from "../../core/template.ts";
import { fail, pageSize, userGrant } from "../shared.ts";
import { subjectTenant } from "../subject-check-sql.ts";
import { conversationTopic } from "./messaging-names.ts";
import { conversationReadable, guestOnRecord } from "./messaging-tables.ts";
import { asText } from "./over-app.ts";

/** `ctx.record` of a conversation event over the row variable `row`. */
function conversationRecord(
  q: MessagingSql,
  type: string,
  row: string,
  extra = "",
): string {
  const cv = q.cols("conversations");

  return q.ctx.record({
    type,
    payload: `jsonb_build_object('organizationId', ${row}.${cv("tenant")}::text, 'conversationId', ${row}.${cv("id")}, 'kind', ${row}.${cv("kind")}, 'subjectType', ${sqlString(q.e("conversation"))}, 'subjectId', ${row}.${cv("id")}::text${extra})`,
    subject: `'conversations/' || ${row}.${cv("id")}::text`,
    tenant: `${row}.${cv("tenant")}::text`,
    audit: false,
  });
}

/** Conversations: opening, members, archiving, reading and following. */
export function conversationFunctions(q: MessagingSql): string {
  const { ctx, t, fn, id } = q;
  const cv = q.cols("conversations");
  const mb = q.cols("members");
  const ms = q.cols("messages");
  const rd = q.cols("reads");
  const subjects = ctx.of("subjects");
  const conversation = sqlString(q.e("conversation"));
  const message = sqlString(q.e("message"));
  const userId = sqlString("userId");

  const memberRecord = (type: string, user: string): string =>
    conversationRecord(q, type, "v_conv", `, ${userId}, ${user}`);

  const kindOf = (alias: string): string =>
    asText(ctx, "conversations", `${alias}.${cv("kind")}`);

  const notify = ctx.has("members", "notify");

  const subscriptions = ctx.installed("notifications")
    ? ctx.of("notifications")
    : undefined;

  const follow =
    subscriptions?.hasTable("subscriptions") === true
      ? (() => {
          const s = (logical: string): string =>
            subscriptions.col("subscriptions", logical);

          const tenanted = subscriptions.has("subscriptions", "tenant");

          return `
-- Follows or unfollows a conversation or a thread (its root message) through
-- the notifications module's subscriptions: following hears of every message
-- (level all), unfollowing ignores it.
create or replace function ${fn("follow")}(target_type text, target_id uuid, following boolean default true)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${id};
  v_type text;
begin
  if follow.target_type = 'conversation' then
    select c.${cv("tenant")} into v_tenant from ${t("conversations")} c
    where c.${cv("id")} = follow.target_id and ${fn("can_conversation")}(c.${cv("id")}, 'read');
    v_type := ${conversation};
  elsif follow.target_type = 'thread' then
    select m.${ms("tenant")} into v_tenant from ${t("messages")} m
    where m.${ms("id")} = follow.target_id and m.${ms("thread")} is null and ${fn("can_conversation")}(m.${ms("conversation")}, 'read');
    v_type := ${message};
  else
    ${fail("MESSAGING_FOLLOW_TARGET", "follow a conversation or a thread", "22023")}
  end if;
  if v_tenant is null then
    ${fail("MESSAGING_NOT_FOUND", "no such conversation or thread you can read", "P0002")}
  end if;
  insert into ${subscriptions.table("subscriptions")} (${[...(tenanted ? [s("tenant")] : []), s("user"), s("subjectType"), s("subjectId"), s("level")].join(", ")})
  values (${[...(tenanted ? ["v_tenant"] : []), "auth.uid()", "v_type", "follow.target_id::text", "case when follow.following then 'all' else 'ignore' end"].join(", ")})
  on conflict (${[...(tenanted ? [s("tenant")] : []), s("user"), s("subjectType"), s("subjectId")].join(", ")}) do update set ${s("level")} = excluded.${s("level")};
  return follow.following;
end;
$$;
${userGrant(`${fn("follow")}(text, uuid, boolean)`)}
`;
        })()
      : "";

  const otherTenant = `coalesce(${subjectTenant(ctx, "(open_conversation.attrs ->> 'subjectType')", "(open_conversation.attrs ->> 'subjectId')")} <> open_conversation.tenant::text, false)`;

  const guestRead = ctx.scope.guest(
    "open_conversation.tenant",
    "open_conversation.attrs ->> 'subjectType'",
    "open_conversation.attrs ->> 'subjectId'",
    "read",
  );

  // A guest granted read on a record opens its conversation (ADR 0070).
  const guestOpen =
    guestRead === "false"
      ? { declare: "", or: "", unless: "" }
      : {
          declare: `\n  v_guest boolean := open_conversation.kind = 'subject' and coalesce(${guestRead}, false);`,
          or: " or v_guest",
          unless: "not v_guest and ",
        };

  const subjectArgs = [
    "(open_conversation.attrs ->> 'subjectType')",
    "(open_conversation.attrs ->> 'subjectId')",
  ] as const;

  const recordFollows = q.followsRecord(`v_conv.${cv("subjectType")}`);

  const recordComment = q.recordCan(
    `v_conv.${cv("subjectType")}`,
    `v_conv.${cv("subjectId")}`,
    "comment",
  );

  const recordModerate = q.recordCan(
    `v_conv.${cv("subjectType")}`,
    `v_conv.${cv("subjectId")}`,
    "moderate",
  );

  const openFollows = q.followsRecord(subjectArgs[0]);
  const openOnRecord = q.recordCan(subjectArgs[0], subjectArgs[1], "comment");

  return `
-- Whether the caller may act on a conversation: read it, send to it (the send
-- key, and membership unless anyone in the tenant may post), or moderate it.
create or replace function ${fn("can_conversation")}(conversation uuid, action text)
returns boolean
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_conv ${t("conversations")};
begin
  select * into v_conv from ${t("conversations")} c
  where c.${cv("id")} = can_conversation.conversation
    and (${q.service} or ${conversationReadable(q, "c")});
  if not found then
    return false;
  end if;
  if ${q.service} then
    return true;
  end if;${
    ctx.installed("inbox")
      ? `
  if v_conv.${cv("kind")} = 'inbox' then
    return ${ctx.of("inbox").fn("inbox_can_conversation")}(v_conv.${cv("id")}, can_conversation.action);
  end if;`
      : ""
  }
  case can_conversation.action
    when 'read' then
      return true;
    when 'send' then${
      recordFollows === undefined
        ? ""
        : `
      if v_conv.${cv("access")} = 'subject' and ${recordFollows} then
        return v_conv.${cv("archivedAt")} is null and ${recordComment ?? "false"};
      end if;`
    }
      return v_conv.${cv("archivedAt")} is null
        and ((${q.can(`v_conv.${cv("tenant")}`, "send")}
        and (v_conv.${cv("access")} <> 'members' or ${fn("is_conversation_member")}(v_conv.${cv("id")})))${guestOnRecord(q, "v_conv", "comment")});
    when 'moderate' then
      return ${q.can(`v_conv.${cv("tenant")}`, "moderate")}${
        recordModerate === undefined
          ? ""
          : `
        or (v_conv.${cv("access")} = 'subject' and ${recordModerate})`
      };
    else
      return false;
  end case;
end;
$$;
${userGrant(`${fn("can_conversation")}(uuid, text)`)}

-- Opens a conversation. kind channel: attrs.title, attrs.access ('members'
-- for a private one, 'tenant' for one anyone in the tenant reads). kind dm or
-- group_dm: the caller and members, one conversation per member set. kind
-- subject: attrs.subjectType and attrs.subjectId, one conversation per
-- record, read by whoever reads the record. Returns the conversation.
create or replace function ${fn("open_conversation")}(tenant ${id}, kind text, attrs jsonb default '{}', members uuid[] default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_users uuid[];
  v_key text;
  v_id uuid;
  v_access text;
  v_conv ${t("conversations")};
  v_created boolean := false;${guestOpen.declare}
begin
  if not (${q.service} or ${q.can("open_conversation.tenant", "send")}${guestOpen.or}${openOnRecord === undefined ? "" : ` or (open_conversation.kind = 'subject' and ${openOnRecord})`}) then
    ${fail("MESSAGING_FORBIDDEN", "not allowed to send messages here")}
  end if;
  v_users := array(
    select distinct x from unnest(coalesce(open_conversation.members, '{}') || case when auth.uid() is null then '{}'::uuid[] else array[auth.uid()] end) x
    where x is not null order by 1
  );
  if ${guestOpen.unless}${openFollows === undefined ? "" : `not (open_conversation.kind = 'subject' and ${openFollows}) and `}exists (
    select 1 from unnest(v_users) x
    where not ${ctx.scope.canUser("x", "open_conversation.tenant", q.key("read"))}
  ) then
    ${fail("MESSAGING_MEMBER_INVALID", "every member must be able to read messages in the organization", "22023")}
  end if;
  case open_conversation.kind
    when 'dm', 'group_dm' then
      if open_conversation.kind = 'dm' and cardinality(v_users) not in (1, 2) then
        ${fail("MESSAGING_DM_MEMBERS", "a direct message has one or two people", "22023")}
      end if;
      if open_conversation.kind = 'group_dm' and cardinality(v_users) not between 3 and 9 then
        ${fail("MESSAGING_GROUP_MEMBERS", "a group message has three to nine people", "22023")}
      end if;
      v_key := array_to_string(v_users, ',');
      select c.${cv("id")} into v_id from ${t("conversations")} c
      where c.${cv("tenant")} = open_conversation.tenant and ${kindOf("c")} = open_conversation.kind and c.${cv("memberKey")} = v_key;
      v_access := 'members';
    when 'subject' then
      if nullif(open_conversation.attrs ->> 'subjectType', '') is null or nullif(open_conversation.attrs ->> 'subjectId', '') is null then
        ${fail("MESSAGING_SUBJECT_REQUIRED", "a record conversation needs attrs.subjectType and attrs.subjectId", "22023")}
      end if;
      if not (${q.service}${guestOpen.or} or coalesce(${subjects.fn("can_subject")}(open_conversation.attrs ->> 'subjectType', open_conversation.attrs ->> 'subjectId', 'read'), false)) then
        ${fail("MESSAGING_NOT_FOUND", "no such record you can read", "P0002")}
      end if;
      -- A record with a tenant column takes conversations in its own tenant only.
      if ${otherTenant} then
        ${fail("MESSAGING_NOT_FOUND", "no such record in this organization", "P0002")}
      end if;
      select c.${cv("id")} into v_id from ${t("conversations")} c
      where c.${cv("tenant")} = open_conversation.tenant and c.${cv("kind")} = 'subject'
        and c.${cv("subjectType")} = open_conversation.attrs ->> 'subjectType' and c.${cv("subjectId")} = open_conversation.attrs ->> 'subjectId';
      v_access := 'subject';
      v_users := '{}';
    when 'channel' then
      v_access := coalesce(open_conversation.attrs ->> 'access', 'members');
      if v_access not in ('members', 'tenant') then
        ${fail("MESSAGING_ACCESS_INVALID", "a channel's access is members or tenant", "22023")}
      end if;
    when 'inbox' then
      if not ${q.service} then
        ${fail("MESSAGING_FORBIDDEN", "the inbox opens its own conversations")}
      end if;
      v_access := 'members';
    else
      ${fail("MESSAGING_KIND_INVALID", "kind is channel, dm, group_dm, subject or inbox", "22023")}
  end case;
  if v_id is null then
    begin
      insert into ${t("conversations")} (${cv("tenant")}, ${cv("kind")}, ${cv("access")}, ${cv("subjectType")}, ${cv("subjectId")}, ${cv("title")}, ${cv("memberKey")}, ${cv("createdBy")})
      values (open_conversation.tenant, ${ctx.cast("conversations", "kind", "open_conversation.kind")}, ${ctx.cast("conversations", "access", "v_access")},
        nullif(open_conversation.attrs ->> 'subjectType', ''), nullif(open_conversation.attrs ->> 'subjectId', ''),
        nullif(trim(open_conversation.attrs ->> 'title'), ''), v_key, auth.uid())
      returning ${cv("id")} into v_id;
      v_created := true;
    exception when unique_violation then
      select c.${cv("id")} into v_id from ${t("conversations")} c
      where c.${cv("tenant")} = open_conversation.tenant and ${kindOf("c")} = open_conversation.kind
        and (c.${cv("memberKey")} = v_key or (c.${cv("subjectType")} = open_conversation.attrs ->> 'subjectType' and c.${cv("subjectId")} = open_conversation.attrs ->> 'subjectId'));
    when check_violation then
      ${fail("MESSAGING_CONVERSATION_INVALID", "a conversation field has an invalid value", "22023")}
    end;
  end if;
  select * into v_conv from ${t("conversations")} c where c.${cv("id")} = v_id;
  if v_created then
    insert into ${t("members")} (${mb("conversation")}, ${mb("tenant")}, ${mb("user")}, ${mb("role")})
    select v_id, open_conversation.tenant, x, ${ctx.cast("members", "role", "case when x = auth.uid() then 'owner' else 'member' end")} from unnest(v_users) x
    on conflict do nothing;
    ${conversationRecord(q, "conversation.created", "v_conv", `, 'recordType', v_conv.${cv("subjectType")}, 'recordId', v_conv.${cv("subjectId")}`)}
  end if;
  return to_jsonb(v_conv);
end;
$$;
${userGrant(`${fn("open_conversation")}(${id}, text, jsonb, uuid[])`)}

-- Adds members. A member adds others to a members-only conversation, anyone
-- who reads a tenant one joins it (users is the caller), and a moderator adds
-- anyone. Direct messages keep their members. Returns how many joined.
create or replace function ${fn("add_conversation_members")}(conversation uuid, users uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_conv ${t("conversations")};
  v_user uuid;
  v_added integer := 0;
begin
  select * into v_conv from ${t("conversations")} c where c.${cv("id")} = add_conversation_members.conversation;
  if not found or not ${fn("can_conversation")}(v_conv.${cv("id")}, 'read') then
    ${fail("MESSAGING_NOT_FOUND", "no such conversation you can read", "P0002")}
  end if;
  if v_conv.${cv("kind")} in ('dm', 'group_dm', 'subject') then
    ${fail("MESSAGING_MEMBERS_FIXED", "this conversation's members can't change", "22023")}
  end if;
  if not (${q.service}
    or ${fn("can_conversation")}(v_conv.${cv("id")}, 'moderate')
    or (${fn("can_conversation")}(v_conv.${cv("id")}, 'send') and (v_conv.${cv("access")} = 'members' or add_conversation_members.users <@ array[auth.uid()]))
    or (v_conv.${cv("access")} = 'tenant' and v_conv.${cv("archivedAt")} is null and add_conversation_members.users <@ array[auth.uid()])) then
    ${fail("MESSAGING_FORBIDDEN", "not allowed to add members here")}
  end if;
  for v_user in select distinct x from unnest(add_conversation_members.users) x where x is not null loop
    if not ${ctx.scope.canUser("v_user", `v_conv.${cv("tenant")}`, q.key("read"))} then
      ${fail("MESSAGING_MEMBER_INVALID", "every member must be able to read messages in the organization", "22023")}
    end if;
    insert into ${t("members")} (${mb("conversation")}, ${mb("tenant")}, ${mb("user")})
    values (v_conv.${cv("id")}, v_conv.${cv("tenant")}, v_user)
    on conflict do nothing;
    if found then
      v_added := v_added + 1;
      ${memberRecord("conversation.member_added", "v_user")}
    end if;
  end loop;
  return v_added;
end;
$$;
${userGrant(`${fn("add_conversation_members")}(uuid, uuid[])`)}

-- Removes a member: the member leaves, or a moderator or the conversation's
-- owner removes them.
create or replace function ${fn("remove_conversation_member")}(conversation uuid, member uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_conv ${t("conversations")};
begin
  select * into v_conv from ${t("conversations")} c where c.${cv("id")} = remove_conversation_member.conversation;
  if not found or not ${fn("can_conversation")}(v_conv.${cv("id")}, 'read') then
    ${fail("MESSAGING_NOT_FOUND", "no such conversation you can read", "P0002")}
  end if;
  if v_conv.${cv("kind")} in ('dm', 'group_dm') then
    ${fail("MESSAGING_MEMBERS_FIXED", "this conversation's members can't change", "22023")}
  end if;
  if not (${q.service}
    or remove_conversation_member.member = auth.uid()
    or ${fn("can_conversation")}(v_conv.${cv("id")}, 'moderate')
    or exists (select 1 from ${t("members")} k where k.${mb("conversation")} = v_conv.${cv("id")} and k.${mb("user")} = auth.uid() and k.${mb("role")} = 'owner')) then
    ${fail("MESSAGING_FORBIDDEN", "not allowed to remove this member")}
  end if;
  delete from ${t("members")} k where k.${mb("conversation")} = v_conv.${cv("id")} and k.${mb("user")} = remove_conversation_member.member;
  if not found then
    return false;
  end if;
  ${memberRecord("conversation.member_removed", "remove_conversation_member.member")}
  return true;
end;
$$;
${userGrant(`${fn("remove_conversation_member")}(uuid, uuid)`)}

-- Archives a conversation (read-only from then on) or restores it: its owner
-- or a moderator.
create or replace function ${fn("archive_conversation")}(conversation uuid, archived boolean default true)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_conv ${t("conversations")};
begin
  select * into v_conv from ${t("conversations")} c where c.${cv("id")} = archive_conversation.conversation;
  if not found or not ${fn("can_conversation")}(v_conv.${cv("id")}, 'read') then
    ${fail("MESSAGING_NOT_FOUND", "no such conversation you can read", "P0002")}
  end if;
  if not (${q.service}
    or ${fn("can_conversation")}(v_conv.${cv("id")}, 'moderate')
    or v_conv.${cv("createdBy")} = auth.uid()
    or exists (select 1 from ${t("members")} k where k.${mb("conversation")} = v_conv.${cv("id")} and k.${mb("user")} = auth.uid() and k.${mb("role")} = 'owner')) then
    ${fail("MESSAGING_FORBIDDEN", "not allowed to archive this conversation")}
  end if;
  update ${t("conversations")} c
  set ${cv("archivedAt")} = case when archive_conversation.archived then coalesce(c.${cv("archivedAt")}, now()) end, ${cv("updatedAt")} = now()
  where c.${cv("id")} = v_conv.${cv("id")}
  returning * into v_conv;
  if archive_conversation.archived then
    ${conversationRecord(q, "conversation.archived", "v_conv")}
  end if;
  return archive_conversation.archived;
end;
$$;
${userGrant(`${fn("archive_conversation")}(uuid, boolean)`)}

-- The caller's conversations, latest message first: those they are a member
-- of, with kinds when given. Each has unread, the caller's unread top-level
-- messages, and mentions, how many of those mention them.
create or replace function ${fn("list_conversations")}(tenant ${id}, kinds text[] default null, max_rows integer default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(
    to_jsonb(c) || jsonb_build_object(
      'unread', u.unread,
      'mentions', u.mentions,
      'lastReadAt', k.${mb("lastReadAt")},
      'notify', ${notify ? `k.${mb("notify")}` : "null"}
    ) order by c.${cv("lastMessageAt")} desc nulls last, c.${cv("id")}), '[]'::jsonb)
  from (
    select c.* from ${t("conversations")} c
    join ${t("members")} k on k.${mb("conversation")} = c.${cv("id")} and k.${mb("user")} = auth.uid()
    where ${ctx.scope.eq(`c.${cv("tenant")}`, "list_conversations.tenant")}
      and (${
        ctx.installed("inbox")
          ? `list_conversations.kinds is null and c.${cv("kind")} <> 'inbox'`
          : "list_conversations.kinds is null"
      } or ${kindOf("c")} = any (list_conversations.kinds))
    order by c.${cv("lastMessageAt")} desc nulls last, c.${cv("id")}
    limit ${pageSize("list_conversations.max_rows", 100, 500)}
  ) c
  join ${t("members")} k on k.${mb("conversation")} = c.${cv("id")} and k.${mb("user")} = auth.uid()
  cross join lateral (
    select count(*) as unread,
      count(*) filter (where auth.uid() = any (m.${ms("mentions")}) or m.${ms("mentionScope")} is not null) as mentions
    from ${t("messages")} m
    where m.${ms("conversation")} = c.${cv("id")}
      and (m.${ms("thread")} is null or m.${ms("broadcast")})
      and m.${ms("sentAt")} > coalesce(k.${mb("lastReadAt")}, '-infinity'::timestamptz)
      and m.${ms("deletedAt")} is null
      and m.${ms("author")} is distinct from auth.uid()
  ) u
$$;
${userGrant(`${fn("list_conversations")}(${id}, text[], integer)`)}

-- Unread top-level messages and mentions per member conversation of the
-- caller in a tenant: { conversationId: { unread, mentions } }, for badges.
create or replace function ${fn("unread_counts")}(tenant ${id})
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(k.${mb("conversation")}::text, jsonb_build_object('unread', u.unread, 'mentions', u.mentions)), '{}'::jsonb)
  from ${t("members")} k
  cross join lateral (
    select count(*) as unread,
      count(*) filter (where auth.uid() = any (m.${ms("mentions")}) or m.${ms("mentionScope")} is not null) as mentions
    from ${t("messages")} m
    where m.${ms("conversation")} = k.${mb("conversation")}
      and (m.${ms("thread")} is null or m.${ms("broadcast")})
      and m.${ms("sentAt")} > coalesce(k.${mb("lastReadAt")}, '-infinity'::timestamptz)
      and m.${ms("deletedAt")} is null
      and m.${ms("author")} is distinct from auth.uid()
  ) u
  where k.${mb("user")} = auth.uid()
    and ${ctx.scope.eq(`k.${mb("tenant")}`, "unread_counts.tenant")}${
      ctx.installed("inbox")
        ? `
    and not exists (select 1 from ${t("conversations")} c where c.${cv("id")} = k.${mb("conversation")} and c.${cv("kind")} = 'inbox')`
        : ""
    }
    and u.unread > 0
$$;
${userGrant(`${fn("unread_counts")}(${id})`)}

-- Marks a conversation (thread null) or a thread read up to read_at, default
-- now. A member's conversation marker lives on their member row; everyone
-- else's, and every thread marker, in thread_reads. Markers only move forward.
create or replace function ${fn("mark_read")}(conversation uuid, thread uuid default null, read_at timestamptz default null)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${id};
  v_at timestamptz := least(coalesce(mark_read.read_at, now()), now());
begin
  if auth.uid() is null then
    ${fail("MESSAGING_SIGNED_OUT", "sign in to mark messages read")}
  end if;
  select c.${cv("tenant")} into v_tenant from ${t("conversations")} c where c.${cv("id")} = mark_read.conversation;
  if v_tenant is null or not ${fn("can_conversation")}(mark_read.conversation, 'read') then
    ${fail("MESSAGING_NOT_FOUND", "no such conversation you can read", "P0002")}
  end if;
  if mark_read.thread is null then
    update ${t("members")} k set ${mb("lastReadAt")} = greatest(coalesce(k.${mb("lastReadAt")}, v_at), v_at)
    where k.${mb("conversation")} = mark_read.conversation and k.${mb("user")} = auth.uid();
    if found then
      return v_at;
    end if;
  elsif not exists (select 1 from ${t("messages")} m where m.${ms("id")} = mark_read.thread and m.${ms("conversation")} = mark_read.conversation and m.${ms("thread")} is null) then
    ${fail("MESSAGING_NOT_FOUND", "no such thread in this conversation", "P0002")}
  end if;
  insert into ${t("reads")} (${rd("tenant")}, ${rd("user")}, ${rd("conversation")}, ${rd("thread")}, ${rd("lastReadAt")})
  values (v_tenant, auth.uid(), mark_read.conversation, mark_read.thread, v_at)
  on conflict (${rd("user")}, ${rd("conversation")}, ${rd("thread")})
  do update set ${rd("lastReadAt")} = greatest(${t("reads")}.${rd("lastReadAt")}, excluded.${rd("lastReadAt")});
  return v_at;
end;
$$;
${userGrant(`${fn("mark_read")}(uuid, uuid, timestamptz)`)}

-- Where user (default the caller) has read a conversation to: the member
-- marker, else the thread_reads one. For counters such as record_summary.
create or replace function ${fn("conversation_read_at")}(conversation uuid, member uuid default null)
returns timestamptz
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(
    (select k.${mb("lastReadAt")} from ${t("members")} k where k.${mb("conversation")} = conversation_read_at.conversation and k.${mb("user")} = coalesce(conversation_read_at.member, auth.uid())),
    (select r.${rd("lastReadAt")} from ${t("reads")} r where r.${rd("conversation")} = conversation_read_at.conversation and r.${rd("user")} = coalesce(conversation_read_at.member, auth.uid()) and r.${rd("thread")} is null)
  )
$$;
${userGrant(`${fn("conversation_read_at")}(uuid, uuid)`)}

-- Sets how a member hears of a conversation: all, mentions or none.
create or replace function ${fn("set_conversation_notify")}(conversation uuid, level text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if set_conversation_notify.level not in ('all', 'mentions', 'none') then
    ${fail("MESSAGING_NOTIFY_INVALID", "level is all, mentions or none", "22023")}
  end if;${
    notify
      ? `
  update ${t("members")} k set ${mb("notify")} = ${ctx.cast("members", "notify", "set_conversation_notify.level")}
  where k.${mb("conversation")} = set_conversation_notify.conversation and k.${mb("user")} = auth.uid();
  return found;`
      : `
  ${fail("MESSAGING_NOTIFY_UNSUPPORTED", "this conversation members table has no notify column", "22023")}`
  }
end;
$$;
${userGrant(`${fn("set_conversation_notify")}(uuid, text)`)}

-- Broadcasts that the caller is typing (or stopped) on the conversation's
-- private topic, for clients that don't send the broadcast themselves. The
-- service names who types in actor (a bot's name), default 'bot'.
drop function if exists ${fn("set_typing")}(uuid, boolean);
create or replace function ${fn("set_typing")}(conversation uuid, typing boolean default true, actor text default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_who text;
begin
  if ${q.service} then
    v_who := coalesce(set_typing.actor, 'bot');
  elsif auth.uid() is null or not ${fn("can_conversation")}(set_typing.conversation, 'send') then
    return false;
  else
    v_who := auth.uid()::text;
  end if;
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is null then
    return false;
  end if;
  perform realtime.send(
    jsonb_build_object(${sqlString(q.e("conversationId"))}, set_typing.conversation, 'userId', v_who, 'typing', coalesce(set_typing.typing, true)),
    'typing',
    ${conversationTopic(q, "set_typing.conversation")},
    true
  );
  return true;
end;
$$;
${userGrant(`${fn("set_typing")}(uuid, boolean, text)`)}
${follow}`;
}
