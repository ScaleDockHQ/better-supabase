import type { MessagingSql } from "./messaging-names.ts";

import { sqlString } from "../../core/template.ts";
import { addExtraColumns, lockTable, triggerGrant } from "../shared.ts";

export const MESSAGE_RESERVED = ["fields"] as const;

/**
 * Whether the caller may read conversation row `alias`: the tenant's read key
 * (or, for a record's conversation, the key on the record through its subject's
 * scope), then membership, the tenant, or the linked record by `access`. It
 * runs as the caller (policies and `security invoker` functions), so
 * `can_subject` reads the record under its own policies. A policy checks the
 * tenant against the set of tenants where the caller holds the key, once per
 * query.
 */
export function conversationReadable(
  q: MessagingSql,
  alias: string,
  options: { readonly policy?: boolean } = {},
): string {
  const cv = q.cols("conversations");
  const tenant = `${alias}.${cv("tenant")}`;

  const inTenant =
    options.policy === true
      ? q.ctx.scope.check(tenant, q.key("read"))
      : q.can(tenant, "read");

  const onRecord = q.onRecord(
    `${alias}.${cv("subjectType")}`,
    `${alias}.${cv("subjectId")}`,
    "read",
  );

  const held =
    onRecord === undefined
      ? inTenant
      : `(${inTenant}
    or (${alias}.${cv("access")} = 'subject' and ${onRecord}))`;

  const readable = `(${held}
    and case ${alias}.${cv("access")}
      when 'tenant' then true
      when 'members' then ${q.fn("is_conversation_member")}(${alias}.${cv("id")})
      when 'subject' then coalesce(${q.ctx.of("subjects").fn("can_subject")}(${alias}.${cv("subjectType")}, ${alias}.${cv("subjectId")}, 'read'), false)
      else false
    end)`;

  if (!q.ctx.installed("inbox")) {
    return readable;
  }

  return `(case when ${alias}.${cv("kind")} = 'inbox'
    then ${q.ctx.of("inbox").fn("inbox_conversation_allowed")}(${alias}.${cv("id")}::text)
    else ${readable} end)`;
}

/** With the inbox: a note shows to the inbox's staff only. */
function noteReadable(q: MessagingSql, conversation: string): string {
  return q.ctx.installed("inbox")
    ? `\n  and (${q.cols("messages")("kind")} = 'message' or ${q.ctx.of("inbox").fn("inbox_note_readable")}(${conversation}))`
    : "";
}

interface TableDdl {
  readonly conversations: string;
  readonly members: string;
  readonly messages: string;
  readonly edits: string;
  readonly reads: string;
}

function tableDdl(q: MessagingSql): TableDdl {
  const { ctx, t, id } = q;
  const cv = q.cols("conversations");
  const mb = q.cols("members");
  const ms = q.cols("messages");
  const ed = q.cols("edits");
  const rd = q.cols("reads");
  const idx = (name: string): string => ctx.naming.rename(name);

  return {
    conversations: `create table if not exists ${t("conversations")} (
  ${cv("id")} uuid primary key default gen_random_uuid(),
  ${cv("tenant")} ${id} not null,
  ${cv("kind")} text not null check (${cv("kind")} in ('channel', 'dm', 'group_dm', 'subject', 'inbox')),
  ${cv("access")} text not null default 'members' check (${cv("access")} in ('members', 'tenant', 'subject')),
  ${cv("subjectType")} text,
  ${cv("subjectId")} text,
  ${cv("title")} text check (${cv("title")} is null or length(${cv("title")}) between 1 and 200),
  ${cv("memberKey")} text,
  ${cv("createdBy")} uuid,
  ${cv("lastMessageAt")} timestamptz,
  ${cv("archivedAt")} timestamptz,
  ${cv("createdAt")} timestamptz not null default now(),
  ${cv("updatedAt")} timestamptz not null default now(),
  check ((${cv("subjectType")} is null) = (${cv("subjectId")} is null)),
  check (${cv("access")} <> 'subject' or ${cv("subjectType")} is not null)
);
create unique index if not exists ${idx("messaging_conversations_subject_idx")} on ${t("conversations")} (${cv("tenant")}, ${cv("subjectType")}, ${cv("subjectId")}) where ${cv("kind")} = 'subject';
create unique index if not exists ${idx("messaging_conversations_member_key_idx")} on ${t("conversations")} (${cv("tenant")}, ${cv("kind")}, ${cv("memberKey")}) where ${cv("memberKey")} is not null;
create index if not exists ${idx("messaging_conversations_list_idx")} on ${t("conversations")} (${cv("tenant")}, ${cv("lastMessageAt")} desc nulls last, ${cv("id")});
${lockTable(t("conversations"), { read: true })}`,
    members: `create table if not exists ${t("members")} (
  ${mb("conversation")} uuid not null references ${t("conversations")} (${cv("id")}) on delete cascade,
  ${mb("tenant")} ${id} not null,
  ${mb("user")} uuid not null,
  ${mb("role")} text not null default 'member' check (${mb("role")} in ('owner', 'member')),
  ${mb("notify")} text not null default 'all' check (${mb("notify")} in ('all', 'mentions', 'none')),
  ${mb("lastReadAt")} timestamptz,
  ${mb("joinedAt")} timestamptz not null default now(),
  primary key (${mb("conversation")}, ${mb("user")})
);
create index if not exists ${idx("messaging_members_user_idx")} on ${t("members")} (${mb("user")}, ${mb("tenant")});
${lockTable(t("members"), { read: true })}`,
    messages: `create table if not exists ${t("messages")} (
  ${ms("id")} uuid primary key default gen_random_uuid(),
  ${ms("tenant")} ${id} not null,
  ${ms("conversation")} uuid not null references ${t("conversations")} (${cv("id")}) on delete cascade,
  ${ms("parent")} uuid references ${t("messages")} (${ms("id")}) on delete set null,
  ${ms("thread")} uuid references ${t("messages")} (${ms("id")}) on delete cascade,
  ${ms("author")} uuid,
  ${ms("kind")} text not null default 'message' check (${ms("kind")} in ('message', 'note')),
  ${ms("body")} text not null default '' check (length(${ms("body")}) <= ${String(q.maxBody)}),
  ${ms("document")} jsonb,
  ${ms("anchor")} jsonb,
  ${ms("mentions")} uuid[] not null default '{}',
  ${ms("mentionScope")} text check (${ms("mentionScope")} in ('channel', 'here')),
  ${ms("broadcast")} boolean not null default false,
  ${ms("replyCount")} integer not null default 0,
  ${ms("lastReplyAt")} timestamptz,
  ${ms("replyUsers")} uuid[] not null default '{}',
  ${ms("pinnedAt")} timestamptz,
  ${ms("pinnedBy")} uuid,
  ${ms("resolvedAt")} timestamptz,
  ${ms("resolvedBy")} uuid,
  ${ms("scheduledFor")} timestamptz,
  ${ms("sentAt")} timestamptz,
  ${ms("editedAt")} timestamptz,
  ${ms("deletedAt")} timestamptz,
  ${ms("createdAt")} timestamptz not null default now(),
  check ((${ms("thread")} is null) = (${ms("parent")} is null))
);
create index if not exists ${idx("messaging_messages_conversation_idx")} on ${t("messages")} (${ms("conversation")}, ${ms("sentAt")}, ${ms("id")}) where ${ms("thread")} is null or ${ms("broadcast")};
create index if not exists ${idx("messaging_messages_thread_idx")} on ${t("messages")} (${ms("thread")}, ${ms("sentAt")}, ${ms("id")}) where ${ms("thread")} is not null;
create index if not exists ${idx("messaging_messages_parent_idx")} on ${t("messages")} (${ms("parent")}) where ${ms("parent")} is not null;
create index if not exists ${idx("messaging_messages_author_idx")} on ${t("messages")} (${ms("author")});
create index if not exists ${idx("messaging_messages_due_idx")} on ${t("messages")} (${ms("scheduledFor")}) where ${ms("sentAt")} is null;
create index if not exists ${idx("messaging_messages_pinned_idx")} on ${t("messages")} (${ms("conversation")}, ${ms("pinnedAt")} desc) where ${ms("pinnedAt")} is not null;${addExtraColumns(t("messages"), ctx.extraColumns("messages", MESSAGE_RESERVED))}
${lockTable(t("messages"), { read: true })}`,
    edits: `create table if not exists ${t("edits")} (
  ${ed("id")} uuid primary key default gen_random_uuid(),
  ${ed("tenant")} ${id} not null,
  ${ed("message")} uuid not null references ${t("messages")} (${ms("id")}) on delete cascade,
  ${ed("body")} text not null,
  ${ed("document")} jsonb,
  ${ed("editor")} uuid,
  ${ed("editedAt")} timestamptz not null default now()
);
create index if not exists ${idx("messaging_edits_message_idx")} on ${t("edits")} (${ed("message")}, ${ed("editedAt")});
${lockTable(t("edits"), { read: true })}`,
    reads: `create table if not exists ${t("reads")} (
  ${rd("tenant")} ${id} not null,
  ${rd("user")} uuid not null,
  ${rd("conversation")} uuid not null references ${t("conversations")} (${cv("id")}) on delete cascade,
  ${rd("thread")} uuid references ${t("messages")} (${ms("id")}) on delete cascade,
  ${rd("lastReadAt")} timestamptz not null default now(),
  unique nulls not distinct (${rd("user")}, ${rd("conversation")}, ${rd("thread")})
);
create index if not exists ${idx("messaging_reads_conversation_idx")} on ${t("reads")} (${rd("conversation")});
create index if not exists ${idx("messaging_reads_thread_idx")} on ${t("reads")} (${rd("thread")});
${lockTable(t("reads"), { read: true })}`,
  };
}

/**
 * The five tables and their indexes, without policies, functions or triggers,
 * for an upgrade step that fills them before the module file runs.
 */
export function messagingTableDdl(q: MessagingSql): string {
  if (!q.ctx.manages) {
    return "";
  }

  const ddl = tableDdl(q);

  return [
    ddl.conversations,
    ddl.members,
    ddl.messages,
    ddl.edits,
    ddl.reads,
  ].join("\n\n");
}

/** The five tables, their policies and the thread and read triggers. */
export function messagingTables(q: MessagingSql): string {
  if (!q.ctx.manages) {
    return "";
  }

  const { ctx, t, fn } = q;
  const ddl = tableDdl(q);
  const cv = q.cols("conversations");
  const mb = q.cols("members");
  const ms = q.cols("messages");
  const ed = q.cols("edits");
  const rd = q.cols("reads");

  const policy = (table: string, suffix: string): string =>
    `${ctx.tableName(table).name}_${suffix}`;

  return `
${ddl.conversations}

${ddl.members}

-- Membership for the conversation policy. It runs as its owner, because the
-- members policy reads conversations and would call it again.
create or replace function ${fn("is_conversation_member")}(conversation uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from ${t("members")} m
    where m.${mb("conversation")} = is_conversation_member.conversation and m.${mb("user")} = auth.uid()
  )
$$;
revoke execute on function ${fn("is_conversation_member")}(uuid) from public, anon;
grant execute on function ${fn("is_conversation_member")}(uuid) to authenticated, service_role;

drop policy if exists ${policy("conversations", "read")} on ${t("conversations")};
create policy ${policy("conversations", "read")} on ${t("conversations")} for select to authenticated
using (${conversationReadable(q, t("conversations"), { policy: true })});

drop policy if exists ${policy("members", "read")} on ${t("members")};
create policy ${policy("members", "read")} on ${t("members")} for select to authenticated
using (
  ${mb("user")} = (select auth.uid())
  or exists (select 1 from ${t("conversations")} c where c.${cv("id")} = ${mb("conversation")})
);

${ddl.messages}

-- A message shows to whoever reads its conversation once it is sent; a
-- scheduled one shows to its author only.
drop policy if exists ${policy("messages", "read")} on ${t("messages")};
create policy ${policy("messages", "read")} on ${t("messages")} for select to authenticated
using (
  (${ms("sentAt")} is not null or ${ms("author")} = (select auth.uid()))
  and exists (select 1 from ${t("conversations")} c where c.${cv("id")} = ${ms("conversation")})${noteReadable(q, ms("conversation"))}
);

${ddl.edits}

drop policy if exists ${policy("edits", "read")} on ${t("edits")};
create policy ${policy("edits", "read")} on ${t("edits")} for select to authenticated
using (exists (select 1 from ${t("messages")} m where m.${ms("id")} = ${ed("message")}));

-- Where a user has read to, per conversation (thread null) or per thread
-- root. Members keep the conversation marker on their member row too; a
-- record's thread has no members, so its readers keep it here.
${ddl.reads}

drop policy if exists ${policy("reads", "read")} on ${t("reads")};
create policy ${policy("reads", "read")} on ${t("reads")} for select to authenticated
using (${rd("user")} = (select auth.uid()));

-- Keeps the thread root's reply count, last reply and first three repliers,
-- and the conversation's last message time, as a reply is sent or deleted.
create or replace function ${fn("messaging_message_written")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.${ms("sentAt")} is null then
    return null;
  end if;
  if tg_op = 'INSERT' or old.${ms("sentAt")} is null then
    update ${t("conversations")} c set ${cv("lastMessageAt")} = greatest(coalesce(c.${cv("lastMessageAt")}, new.${ms("sentAt")}), new.${ms("sentAt")}), ${cv("updatedAt")} = now()
    where c.${cv("id")} = new.${ms("conversation")};
  end if;
  if new.${ms("thread")} is not null and (tg_op = 'INSERT' or old.${ms("sentAt")} is null or new.${ms("deletedAt")} is distinct from old.${ms("deletedAt")}) then
    update ${t("messages")} r set
      ${ms("replyCount")} = (select count(*) from ${t("messages")} x where x.${ms("thread")} = r.${ms("id")} and x.${ms("sentAt")} is not null and x.${ms("deletedAt")} is null),
      ${ms("lastReplyAt")} = (select max(x.${ms("sentAt")}) from ${t("messages")} x where x.${ms("thread")} = r.${ms("id")} and x.${ms("deletedAt")} is null),
      ${ms("replyUsers")} = array(
        select y.u from (
          select x.${ms("author")} as u, min(x.${ms("sentAt")}) as first
          from ${t("messages")} x
          where x.${ms("thread")} = r.${ms("id")} and x.${ms("sentAt")} is not null and x.${ms("deletedAt")} is null and x.${ms("author")} is not null
          group by x.${ms("author")}
        ) y order by y.first limit 3
      )
    where r.${ms("id")} = new.${ms("thread")};
  end if;
  return null;
end;
$$;
${triggerGrant(`${fn("messaging_message_written")}()`)}
drop trigger if exists ${ctx.trigger("messaging_message_written")} on ${t("messages")};
create trigger ${ctx.trigger("messaging_message_written")} after insert or update of ${ms("sentAt")}, ${ms("deletedAt")} on ${t("messages")}
  for each row execute function ${fn("messaging_message_written")}();
`;
}

/**
 * Realtime: a ping with ids only on \`<topic>:<conversation>\` for each sent,
 * edited or deleted message, and the policies that let a reader of the
 * conversation join that private topic and send typing broadcasts and presence
 * on it.
 */
export function messagingRealtime(q: MessagingSql): string {
  const { ctx, t, fn } = q;
  const ms = q.cols("messages");
  const cv = q.cols("conversations");
  const ready = `to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null`;
  const receive = ctx.trigger("messaging_receive");
  const broadcast = ctx.trigger("messaging_broadcast");
  const prefix = sqlString(`${q.topic}:`);
  const start = String(q.topic.length + 2);

  return `
-- Whether the caller reads conversation \`id\` (text, from a topic name).
create or replace function ${fn("conversation_topic_allowed")}(id text)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when conversation_topic_allowed.id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      then exists (select 1 from ${t("conversations")} c where c.${cv("id")} = conversation_topic_allowed.id::uuid)
    else false
  end
$$;
revoke execute on function ${fn("conversation_topic_allowed")}(text) from public, anon;
grant execute on function ${fn("conversation_topic_allowed")}(text) to authenticated, service_role;

create or replace function ${fn("messaging_message_broadcast")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if ${ready} and new.${ms("sentAt")} is not null then
    perform realtime.send(
      jsonb_build_object(${sqlString(q.e("conversationId"))}, new.${ms("conversation")}, ${sqlString(q.e("messageId"))}, new.${ms("id")}, 'threadId', new.${ms("thread")}),
      case when tg_op = 'INSERT' or old.${ms("sentAt")} is null then 'message' when new.${ms("deletedAt")} is not null then 'message_deleted' else 'message_updated' end,
      ${prefix} || new.${ms("conversation")}::text,
      true
    );
  end if;
  return null;
end;
$$;
${triggerGrant(`${fn("messaging_message_broadcast")}()`)}
drop trigger if exists ${ctx.trigger("messaging_message_broadcast")} on ${t("messages")};
create trigger ${ctx.trigger("messaging_message_broadcast")} after insert or update on ${t("messages")}
  for each row execute function ${fn("messaging_message_broadcast")}();

do $$
begin
  if to_regclass('realtime.messages') is not null then
    drop policy if exists ${receive} on realtime.messages;
    create policy ${receive} on realtime.messages for select to authenticated
      using (
        realtime.messages.extension in ('broadcast', 'presence')
        and (select realtime.topic()) like ${prefix} || '%'
        and ${fn("conversation_topic_allowed")}(substr((select realtime.topic()), ${start}))
      );
    drop policy if exists ${broadcast} on realtime.messages;
    create policy ${broadcast} on realtime.messages for insert to authenticated
      with check (
        realtime.messages.extension in ('broadcast', 'presence')
        and (select realtime.topic()) like ${prefix} || '%'
        and ${fn("conversation_topic_allowed")}(substr((select realtime.topic()), ${start}))
      );
  end if;
end;
$$;
`;
}
