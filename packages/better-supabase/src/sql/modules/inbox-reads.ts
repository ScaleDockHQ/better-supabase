import type { InboxSql } from "./inbox-names.ts";

import { fail, pageSize } from "../shared.ts";
import { forbidden, missing } from "./inbox-names.ts";

/** The reads: conversation and message pages, one of each, events and counts. */
export function inboxReadFunctions(q: InboxSql): string {
  const { id, fn } = q;
  const ct = q.cols("contacts");
  const cv = q.cols("conversations");
  const ev = q.cols("events");
  const T = (name: string): string => q.t(name);
  const core = q.core;
  const cm = core.cols("messages");
  const ck = core.cols("members");
  const conversationJson = fn("inbox_conversation_json");
  const messagesJson = fn("inbox_messages_json");

  const authed = (signature: string): string =>
    `revoke execute on function ${signature} from public, anon;
grant execute on function ${signature} to authenticated, service_role;`;

  const searched = (
    [
      ["conversations", "v", "subject"],
      ["conversations", "v", "preview"],
      ["contacts", "c", "name"],
      ["contacts", "c", "email"],
    ] as const
  )
    .filter(([table, , column]) => q.has(table, column))
    .map(([table, alias, column]) => `${alias}.${q.cols(table)(column)}`);

  return `-- Conversations the caller reads (staff of the tenant, or a contact's own),
-- newest activity first. filter: inbox_id, status ('all' for every status),
-- assignee ('me', 'unassigned' or an id), team_id, contact_id, search,
-- before ({ last_message_at, id } of the previous page's last item), limit.
create or replace function ${fn("list_inbox_conversations")}(tenant ${id} default null, filter jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
begin
  return (
    select coalesce(jsonb_agg(${conversationJson}(page.${cv("id")}) || jsonb_build_object('unread', page.unread) order by page.${cv("lastMessageAt")} desc, page.${cv("id")} desc), '[]'::jsonb)
    from (
      select v.${cv("id")}, v.${cv("lastMessageAt")},
        v.${cv("lastMessageAt")} > coalesce((select k.${ck("lastReadAt")} from ${core.t("members")} k where k.${ck("conversation")} = v.${cv("id")} and k.${ck("user")} = (select auth.uid())), '-infinity'::timestamptz) as unread
      from ${T("conversations")} v
      left join ${T("contacts")} c on c.${ct("id")} = v.${cv("contact")}
      where (list_inbox_conversations.tenant is null or v.${cv("tenant")} = list_inbox_conversations.tenant)
        and (filter ->> 'inbox_id' is null or v.${cv("inbox")} = (filter ->> 'inbox_id')::uuid)
        and (coalesce(filter ->> 'status', 'open') = 'all' or ${q.text("conversations", `v.${cv("status")}`)} = coalesce(filter ->> 'status', 'open'))
        and (case filter ->> 'assignee'
          when 'me' then v.${cv("assignee")} = (select auth.uid())
          when 'unassigned' then v.${cv("assignee")} is null
          else filter ->> 'assignee' is null or v.${cv("assignee")} = (filter ->> 'assignee')::uuid end)
        and (filter ->> 'team_id' is null or v.${cv("team")} = (filter ->> 'team_id')::uuid)
        and (filter ->> 'contact_id' is null or v.${cv("contact")} = (filter ->> 'contact_id')::uuid)
        and (nullif(filter ->> 'search', '') is null${searched
          .map(
            (column) => `
          or ${column} ilike '%' || (filter ->> 'search') || '%'`,
          )
          .join("")})
        and (filter -> 'before' is null
          or (v.${cv("lastMessageAt")}, v.${cv("id")}) < ((filter -> 'before' ->> 'last_message_at')::timestamptz, (filter -> 'before' ->> 'id')::uuid))
      order by v.${cv("lastMessageAt")} desc, v.${cv("id")} desc
      limit ${pageSize("(filter ->> 'limit')::integer", 50, 200)}
    ) page
  );
end;
$$;
${authed(`${fn("list_inbox_conversations")}(${id}, jsonb)`)}

create or replace function ${fn("get_conversation")}(conversation uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select ${conversationJson}(v.${cv("id")}) from ${T("conversations")} v where v.${cv("id")} = ${q.ctx.owns("conversations") ? "conversation" : "get_conversation.conversation"};
$$;
${authed(`${fn("get_conversation")}(uuid)`)}

-- A page of messages, oldest first, sent before the given instant. Staff
-- also get notes and each outbound message's delivery.
create or replace function ${fn("list_inbox_messages")}(conversation uuid, before timestamptz default null, max integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ${fn("inbox_conversation_allowed")}(list_inbox_messages.conversation::text) then
    return '[]'::jsonb;
  end if;
  return ${messagesJson}(array(
    select m.${cm("id")} from ${core.t("messages")} m
    where m.${cm("conversation")} = list_inbox_messages.conversation
      and m.${cm("sentAt")} is not null
      and (list_inbox_messages.before is null or m.${cm("sentAt")} < list_inbox_messages.before)
      and (m.${cm("kind")} = 'message' or ${fn("inbox_note_readable")}(list_inbox_messages.conversation))
    order by m.${cm("sentAt")} desc, m.${cm("id")} desc
    limit ${pageSize("list_inbox_messages.max", 50, 200)}
  ));
end;
$$;
${authed(`${fn("list_inbox_messages")}(uuid, timestamptz, integer)`)}

-- One message as list_inbox_messages returns it, for a Realtime ping.
create or replace function ${fn("get_inbox_message")}(message uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select ${messagesJson}(array[get_inbox_message.message]) -> 0;
$$;
${authed(`${fn("get_inbox_message")}(uuid)`)}

-- The conversation's activity log, for staff.
create or replace function ${fn("list_conversation_events")}(conversation uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(${q.json("events", "e")} order by e.${ev("id")}), '[]'::jsonb)
  from ${T("events")} e where e.${ev("conversation")} = list_conversation_events.conversation;
$$;
${authed(`${fn("list_conversation_events")}(uuid)`)}

-- Counts of open conversations for the caller: all, assigned to them,
-- unassigned, and those with activity since they last read them.
create or replace function ${fn("inbox_counts")}(tenant ${id})
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
begin
  return (
    select jsonb_build_object(
      'open', count(*),
      'mine', count(*) filter (where v.${cv("assignee")} = (select auth.uid())),
      'unassigned', count(*) filter (where v.${cv("assignee")} is null),
      'unread', count(*) filter (where v.${cv("lastMessageAt")} > coalesce(k.${ck("lastReadAt")}, '-infinity'::timestamptz)
        and (v.${cv("assignee")} is null or v.${cv("assignee")} = (select auth.uid())))
    )
    from ${T("conversations")} v
    left join ${core.t("members")} k on k.${ck("conversation")} = v.${cv("id")} and k.${ck("user")} = (select auth.uid())
    where v.${cv("tenant")} = inbox_counts.tenant and v.${cv("status")} = 'open'
  );
end;
$$;
${authed(`${fn("inbox_counts")}(${id})`)}`;
}

/**
 * `react_to_inbox_message` with the `reactions` module: the caller's reaction
 * on a core message, kept in that module's table, with a ping on the
 * conversation topic. Without the module it refuses.
 */
export function inboxReactFunction(q: InboxSql): string {
  const { fn, core } = q;
  const cm = core.cols("messages");
  const dt = q.cols("details");
  const ctx = q.ctx;
  const signature = `${fn("react_to_inbox_message")}(uuid, text, boolean, text)`;

  const authed = `revoke execute on function ${signature} from public, anon;
grant execute on function ${signature} to authenticated, service_role;`;

  const head = `-- Adds or removes the caller's reaction on a message (staff with the reply
-- key on a note); the service passes actor (a user id, or a name such as the
-- bot's). Returns the message's reactions.
create or replace function ${fn("react_to_inbox_message")}(message uuid, emoji text, present boolean default true, actor text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$`;

  if (!ctx.installed("reactions") || ctx.of("reactions").mode === "custom") {
    return `${head}
begin
  ${fail("INBOX_REACTIONS_MISSING", "install the reactions block to react to messages", "0A000")}
end;
$$;
${authed}`;
  }

  const reactions = ctx.of("reactions");
  const table = reactions.table("reactions");
  const r = (column: string): string => reactions.col("reactions", column);

  return `${head}
declare
  v_msg ${core.t("messages")}%rowtype;
  v_conversation uuid;
  v_who text;
begin
  select m.* into v_msg from ${core.t("messages")} m
  join ${q.t("details")} d on d.${dt("message")} = m.${cm("id")}
  where m.${cm("id")} = react_to_inbox_message.message and m.${cm("deletedAt")} is null;
  if not found then
    ${missing("message", "MESSAGE_NOT_FOUND")}
  end if;
  v_conversation := v_msg.${cm("conversation")};
  if ${q.service} then
    v_who := coalesce(react_to_inbox_message.actor, 'bot');
  elsif v_msg.${cm("kind")} = 'message' and ${fn("inbox_conversation_allowed")}(v_conversation::text, true) then
    v_who := (select auth.uid())::text;
  elsif v_msg.${cm("kind")} = 'note' and ${q.can(`v_msg.${cm("tenant")}`, "reply")} then
    v_who := (select auth.uid())::text;
  else
    ${forbidden("not allowed to react to this message")}
  end if;
  if length(react_to_inbox_message.emoji) not between 1 and 64 then
    ${fail("INBOX_REACTION_INVALID", "emoji must be 1 to 64 characters", "22023")}
  end if;
  if coalesce(react_to_inbox_message.present, true) then
    insert into ${table} (${r("tenant")}, ${r("subjectType")}, ${r("subjectId")}, ${r("actor")}, ${r("user")}, ${r("emoji")})
    values (v_msg.${cm("tenant")}, ${core.message}, v_msg.${cm("id")}::text, v_who, case when v_who ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then v_who::uuid end, react_to_inbox_message.emoji)
    on conflict do nothing;
  else
    delete from ${table} x
    where x.${r("subjectType")} = ${core.message} and x.${r("subjectId")} = v_msg.${cm("id")}::text
      and x.${r("actor")} = v_who and x.${r("emoji")} = react_to_inbox_message.emoji;
  end if;
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send(
      jsonb_build_object('conversationId', v_conversation, 'messageId', v_msg.${cm("id")}),
      'message_updated',
      ${core.topic("v_conversation")},
      true
    );
  end if;
  return coalesce(${reactions.fn("reaction_summary")}(v_msg.${cm("tenant")}, ${core.message}, array[v_msg.${cm("id")}::text]) -> v_msg.${cm("id")}::text, '[]'::jsonb);
end;
$$;
${authed}`;
}

/** When the contact last read a conversation, for staff read receipts. */
export function inboxContactReadAt(q: InboxSql): string {
  const { fn } = q;
  const ct = q.cols("contacts");
  const cv = q.cols("conversations");
  const ck = q.core.cols("members");

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
    from ${q.t("conversations")} v
    join ${q.t("contacts")} c on c.${ct("id")} = v.${cv("contact")}
    join ${q.core.t("members")} k on k.${ck("conversation")} = v.${cv("id")} and k.${ck("user")} = c.${ct("user")}
    where v.${cv("id")} = inbox_contact_read_at.conversation
      and (${q.service} or ${q.can(`v.${cv("tenant")}`, "read")})
  );
end;
$$;
revoke execute on function ${fn("inbox_contact_read_at")}(uuid) from public, anon;
grant execute on function ${fn("inbox_contact_read_at")}(uuid) to authenticated, service_role;`;
}
