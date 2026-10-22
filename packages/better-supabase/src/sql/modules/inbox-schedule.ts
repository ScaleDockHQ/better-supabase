import type { InboxSql } from "./inbox-names.ts";

import { serviceGrant, fail } from "../shared.ts";
import { forbidden, missing } from "./inbox-names.ts";

/**
 * Snooze wake-ups and scheduled replies: staff schedule a reply for later, a
 * delayed job (or a periodic sweep) publishes it through the normal reply path,
 * and snoozed conversations reopen with an event and a notification.
 */
export function inboxScheduleFunctions(q: InboxSql): string {
  const { fn, ctx } = q;
  const cv = q.cols("conversations");
  const ev = q.cols("events");
  const mb = q.cols("members");
  const sm = q.cols("scheduled");
  const T = (name: string): string => q.t(name);

  const authed = (signature: string): string =>
    `revoke execute on function ${signature} from public, anon;
grant execute on function ${signature} to authenticated, service_role;`;

  const notifyOn = ctx.installed("notifications") && ctx.flag("notify", true);
  const notifyDeclare = notifyOn ? "\n  v_claims text;" : "";

  const audience = `case when v_conv.${cv("assignee")} is not null then to_jsonb(array[v_conv.${cv("assignee")}])
    else coalesce((select jsonb_agg(m.${mb("user")}) from ${T("members")} m where m.${mb("inbox")} = v_conv.${cv("inbox")}), '[]'::jsonb) end`;

  const log = (type: string, actor: string, data: string): string =>
    `insert into ${T("events")} (${ev("tenant")}, ${ev("conversation")}, ${ev("type")}, ${ev("actor")}, ${ev("data")})
    values (v_conv.${cv("tenant")}, v_conv.${cv("id")}, '${type}', ${actor}, ${data});`;

  const woken = ctx.record({
    type: "inbox_conversation.unsnoozed",
    payload: `jsonb_build_object('conversationId', v_conv.${cv("id")}, 'organizationId', v_conv.${cv("tenant")}::text, 'inboxId', v_conv.${cv("inbox")}, 'contactId', v_conv.${cv("contact")}, 'assigneeId', v_conv.${cv("assignee")}, 'status', v_conv.${cv("status")})`,
    subject: `'conversations/' || v_conv.${cv("id")}::text`,
    tenant: `v_conv.${cv("tenant")}`,
    audit: false,
  });

  const wakeNotice = notifyOn
    ? `
    ${ctx.notify(
      `jsonb_build_object(
      'type', 'inbox.snooze_ended',
      'tenant', v_conv.${cv("tenant")},
      'subject_type', 'conversation',
      'subject_id', v_conv.${cv("id")}::text,
      'summary', coalesce(v_conv.${cv("subject")}, v_conv.${cv("preview")}),
      'recipients', ${audience},
      'key', 'inbox.snooze_ended:' || v_conv.${cv("id")}::text || ':' || extract(epoch from v_until)::text,
      'data', jsonb_build_object('conversationId', v_conv.${cv("id")})
    )`,
      { indent: "    " },
    )}`
    : "";

  // A job at scheduled_for publishes the message; an earlier job left by a
  // reschedule finds nothing due and does nothing.
  const publishJob = (row: string): string =>
    ctx.enqueue(
      q.scheduleQueue,
      `jsonb_build_object('type', 'inbox.publish', 'scheduled_id', ${row}.${sm("id")})`,
      `'inbox-publish:' || ${row}.${sm("id")}::text || ':' || extract(epoch from ${row}.${sm("scheduledFor")})::text`,
      {
        delay: `greatest(ceil(extract(epoch from (${row}.${sm("scheduledFor")} - now())))::integer, 0)`,
      },
    );

  const future = (
    value: string,
  ): string => `if ${value} is null or ${value} <= now() then
    ${fail("INBOX_SCHEDULE_TIME", "scheduled_for must be in the future", "22023")}
  end if;`;

  // The author's own scheduled message, locked; anyone else gets not found.
  const loadOwn = (
    param: string,
  ): string => `select * into v_row from ${T("scheduled")} where ${sm("id")} = ${param} and ${sm("author")} = (select auth.uid()) for update;
  if not found then
    ${missing("scheduled message", "SCHEDULED_MESSAGE_NOT_FOUND")}
  end if;`;

  return `-- Reopens snoozed conversations whose time came: the delayed job from
-- set_conversation_status, or a periodic sweep. Each one logs unsnoozed, emits
-- inbox_conversation.unsnoozed and tells the assignee (or the inbox's members).
create or replace function ${fn("wake_snoozed_conversations")}()
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_conv ${T("conversations")}%rowtype;
  v_until timestamptz;
  v_count integer := 0;${notifyDeclare}
begin
  for v_conv in
    select * from ${T("conversations")}
    where ${cv("status")} = 'snoozed' and ${cv("snoozedUntil")} <= now()
    order by ${cv("snoozedUntil")}
    for update skip locked
  loop
    v_until := v_conv.${cv("snoozedUntil")};
    update ${T("conversations")} set ${cv("status")} = 'open', ${cv("snoozedUntil")} = null
    where ${cv("id")} = v_conv.${cv("id")}
    returning * into v_conv;
    ${log("unsnoozed", "null", "jsonb_build_object('snoozed_until', v_until)")}
    ${woken}${wakeNotice}
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
${serviceGrant(`${fn("wake_snoozed_conversations")}()`)}

-- Schedules a staff reply on the conversation for scheduled_for. Only
-- messages: notes post right away. The input is the one send_inbox_message
-- takes, without the service's fields.
create or replace function ${fn("schedule_inbox_message")}(conversation uuid, input jsonb, scheduled_for timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_conv ${T("conversations")}%rowtype;
  v_row ${T("scheduled")}%rowtype;
  v_input jsonb := coalesce(input, '{}'::jsonb) - 'files' - 'external_id' - 'author_type' - 'delivered_by_caller';
begin
  select * into v_conv from ${T("conversations")} where ${cv("id")} = schedule_inbox_message.conversation;
  if not found then
    ${missing("conversation", "CONVERSATION_NOT_FOUND")}
  end if;
  if (select auth.uid()) is null or not ${q.command(`v_conv.${cv("tenant")}`, "reply", "reply")} then
    ${forbidden("not allowed to reply in this conversation")}
  end if;
  if coalesce(v_input ->> 'kind', 'message') <> 'message' then
    ${fail("INBOX_KIND_INVALID", "only messages can be scheduled", "22023")}
  end if;
  if length(btrim(coalesce(v_input ->> 'body', ''))) = 0 and coalesce(jsonb_array_length(v_input -> 'attachments'), 0) = 0 then
    ${fail("INBOX_MESSAGE_EMPTY", "a message needs a body or an attachment", "22023")}
  end if;
  if length(coalesce(v_input ->> 'body', '')) > ${String(q.maxBody)} then
    ${fail("INBOX_MESSAGE_TOO_LONG", `a message is at most ${String(q.maxBody)} characters`, "22023")}
  end if;
  ${future("schedule_inbox_message.scheduled_for")}
  insert into ${T("scheduled")} (${sm("tenant")}, ${sm("conversation")}, ${sm("author")}, ${sm("input")}, ${sm("scheduledFor")})
  values (v_conv.${cv("tenant")}, v_conv.${cv("id")}, (select auth.uid()), v_input, schedule_inbox_message.scheduled_for)
  returning * into v_row;
  ${publishJob("v_row")}
  return to_jsonb(v_row);
end;
$$;
${authed(`${fn("schedule_inbox_message")}(uuid, jsonb, timestamptz)`)}

-- The caller's scheduled messages, soonest first; on one conversation when
-- conversation is set.
create or replace function ${fn("list_scheduled_inbox_messages")}(conversation uuid default null)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(s) order by s.${sm("scheduledFor")}, s.${sm("id")}), '[]'::jsonb)
  from ${T("scheduled")} s
  where s.${sm("author")} = (select auth.uid())
    and (list_scheduled_inbox_messages.conversation is null or s.${sm("conversation")} = list_scheduled_inbox_messages.conversation);
$$;
${authed(`${fn("list_scheduled_inbox_messages")}(uuid)`)}

-- Moves the caller's scheduled message to another time in the future.
create or replace function ${fn("reschedule_inbox_message")}(scheduled uuid, scheduled_for timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${T("scheduled")}%rowtype;
begin
  ${loadOwn("reschedule_inbox_message.scheduled")}
  ${future("reschedule_inbox_message.scheduled_for")}
  update ${T("scheduled")} set ${sm("scheduledFor")} = reschedule_inbox_message.scheduled_for
  where ${sm("id")} = v_row.${sm("id")}
  returning * into v_row;
  ${publishJob("v_row")}
  return to_jsonb(v_row);
end;
$$;
${authed(`${fn("reschedule_inbox_message")}(uuid, timestamptz)`)}

-- Deletes the caller's scheduled message before it is sent.
create or replace function ${fn("cancel_inbox_message")}(scheduled uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${T("scheduled")}%rowtype;
begin
  ${loadOwn("cancel_inbox_message.scheduled")}
  delete from ${T("scheduled")} where ${sm("id")} = v_row.${sm("id")};
  return true;
end;
$$;
${authed(`${fn("cancel_inbox_message")}(uuid)`)}

-- Sends the scheduled messages whose time came, oldest first, as their
-- authors. A message whose author can no longer reply is dropped. Returns
-- the number sent.
create or replace function ${fn("publish_due_inbox_messages")}(max_rows integer default 100)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${T("scheduled")}%rowtype;
  v_conv ${T("conversations")}%rowtype;
  v_count integer := 0;
begin
  for v_row in
    select * from ${T("scheduled")}
    where ${sm("scheduledFor")} <= now()
    order by ${sm("scheduledFor")}, ${sm("id")}
    limit greatest(coalesce(max_rows, 100), 1)
    for update skip locked
  loop
    delete from ${T("scheduled")} where ${sm("id")} = v_row.${sm("id")};
    if not ${ctx.scope.canUser(`v_row.${sm("author")}`, `v_row.${sm("tenant")}`, q.key("reply"))} then
      continue;
    end if;
    perform ${fn("inbox_add_message")}(v_row.${sm("conversation")}, v_row.${sm("input")}, 'agent', v_row.${sm("author")}, 'outbound');
    select * into v_conv from ${T("conversations")} where ${cv("id")} = v_row.${sm("conversation")};
    if v_conv.${cv("botMode")} = 'bot' then
      update ${T("conversations")} set ${cv("botMode")} = 'human' where ${cv("id")} = v_conv.${cv("id")} returning * into v_conv;
      ${log("handoff", `v_row.${sm("author")}`, "jsonb_build_object('from', 'bot', 'to', 'human', 'reason', 'agent_reply')")}
    end if;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
${serviceGrant(`${fn("publish_due_inbox_messages")}(integer)`)}`;
}
