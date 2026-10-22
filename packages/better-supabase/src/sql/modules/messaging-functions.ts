import type { MessagingSql } from "./messaging-names.ts";

import { sqlString } from "../../core/template.ts";
import {
  fail,
  pageSize,
  serviceGrant,
  userGrant,
  withExtraFields,
  writeExtraColumns,
} from "../shared.ts";
import { registeredSubjects } from "../subject-registry.ts";
import { watchSql } from "../watch-sql.ts";
import { authorLookup } from "./authors.ts";
import { conversationFunctions } from "./messaging-conversations.ts";
import { summaryFunctions } from "./messaging-summaries.ts";
import { MESSAGE_RESERVED, conversationReadable } from "./messaging-tables.ts";

const UUID = "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}";
const MAX_UUID = "'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid";

/** The most records one message's mentions index. */
const MAX_RECORD_MENTIONS = 20;

/** `messaging_messages_json`: messages as the clients read them. */
function messagesJson(q: MessagingSql): string {
  const { ctx, t, fn } = q;
  const ms = q.cols("messages");
  const extras = ctx.extraColumns("messages", MESSAGE_RESERVED);
  const message = sqlString(q.e("message"));

  const authors = authorLookup(ctx, {
    name: "message_authors",
    table: t("messages"),
    id: ms("id"),
    user: ms("author"),
    visible: `exists (select 1 from ${t("conversations")} c where c.${q.cols("conversations")("id")} = y.${ms("conversation")} and ${conversationReadable(q, "c")})`,
    what: "The name and avatar of each message's author, keyed by message id,\n-- for the messages of ids the caller may read.",
  });

  const files = ctx.installed("attachments")
    ? (() => {
        const at = ctx.of("attachments");
        const a = (column: string): string => at.col("attachments", column);

        return `,
  f as (
    select coalesce(jsonb_object_agg(g.id, g.files), '{}'::jsonb) as files
    from (
      select a.${a("subjectId")} as id, jsonb_agg(jsonb_build_object('id', a.${a("id")}, 'name', a.${a("name")}, 'mimeType', a.${a("mimeType")}, 'size', a.${a("size")}, 'status', a.${a("status")}) order by a.${a("createdAt")}, a.${a("id")}) as files
      from ${at.table("attachments")} a
      where a.${a("subjectType")} = ${message}
        and a.${a("subjectId")} = any (array(select x::text from unnest(messaging_messages_json.ids) x))
        and a.${a("status")} <> 'infected'
      group by a.${a("subjectId")}
    ) g
  )`;
      })()
    : "";

  const reactions = ctx.installed("reactions")
    ? `,
  r as (
    select coalesce(jsonb_object_agg(g.tenant, ${ctx.of("reactions").fn("reaction_summary")}(g.tenant, ${message}, g.ids)), '{}'::jsonb) as reactions
    from (
      select m.${ms("tenant")} as tenant, array_agg(m.${ms("id")}::text) as ids from page_rows m group by m.${ms("tenant")}
    ) g
  )`
    : "";

  const json = [
    withExtraFields("to_jsonb(x)", "x", extras),
    ...(authors
      ? ["jsonb_build_object('author', a.authors -> x.id::text)"]
      : []),
    ...(files
      ? [
          "jsonb_build_object('attachments', coalesce(f.files -> x.id::text, '[]'::jsonb))",
        ]
      : []),
    ...(reactions
      ? [
          `jsonb_build_object('reactions', coalesce(r.reactions -> x.${ms("tenant")}::text -> x.id::text, '[]'::jsonb))`,
        ]
      : []),
  ].join(" || ");

  const from = [
    "page_rows x",
    ...(authors ? ["a"] : []),
    ...(files ? ["f"] : []),
    ...(reactions ? ["r"] : []),
  ].join(", ");

  return `${authors?.sql ?? ""}

-- The messages of ids the caller may read, oldest first, each with its
-- author, files and reactions when those modules are installed.
create or replace function ${fn("messaging_messages_json")}(ids uuid[])
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with page_rows as (
    select m.* from ${t("messages")} m where m.${ms("id")} = any (messaging_messages_json.ids)
  )${authors ? `,\n  a as (select ${authors.call("messaging_messages_json.ids")} as authors)` : ""}${files}${reactions}
  select coalesce(jsonb_agg(${json} order by coalesce(x.${ms("sentAt")}, x.${ms("scheduledFor")}, x.${ms("createdAt")}), x.${ms("id")}), '[]'::jsonb)
  from ${from}
$$;
${userGrant(`${fn("messaging_messages_json")}(uuid[])`)}`;
}

/**
 * The service-role notifications and the event of a message once it is sent:
 * mentions, direct messages and replies to followed threads.
 */
function sentEffects(q: MessagingSql): string {
  const { ctx, t, fn } = q;
  const ms = q.cols("messages");
  const cv = q.cols("conversations");
  const mb = q.cols("members");
  const rm = q.cols("recordMentions");
  const message = sqlString(q.e("message"));
  const messageId = sqlString(q.e("messageId"));
  const notifications = ctx.installed("notifications");

  const notify = (type: string, extra: string): string =>
    ctx.notify(
      `jsonb_build_object(
      'type', ${sqlString(q.e(type))},
      'tenant', v_msg.${ms("tenant")},
      'actor', v_msg.${ms("author")},
      'subject_type', ${message},
      'subject_id', coalesce(v_msg.${ms("thread")}, v_msg.${ms("id")})::text,
      'summary', left(v_msg.${ms("body")}, 140),
      'data', jsonb_build_object(${messageId}, v_msg.${ms("id")}, ${sqlString(q.e("conversationId"))}, v_msg.${ms("conversation")})${extra}
    )`,
      { indent: "    " },
    );

  // A record type with a read key in config.subjects asks can_subject_for;
  // other records only have their row policies, which answer for the caller.
  const keyed = registeredSubjects(ctx.subjects, ctx.naming)
    .filter((subject) => subject.config.permissions?.["read"] !== undefined)
    .map((subject) => subject.type);

  const readsRecord = (user: string): string =>
    keyed.length === 0
      ? ""
      : `
        and (v_conv.${cv("access")} <> 'subject' or case v_conv.${cv("subjectType")} ${keyed
          .map(
            (type) =>
              `when ${sqlString(type)} then coalesce(${ctx.of("subjects").fn("can_subject_for")}(${user}, v_conv.${cv("subjectType")}, v_conv.${cv("subjectId")}, 'read'), false)`,
          )
          .join(" ")} else true end)`;

  const canRead = (user: string): string =>
    `${ctx.scope.canUser(user, `v_msg.${ms("tenant")}`, q.key("read"))}
        and (v_conv.${cv("access")} <> 'members' or exists (select 1 from ${t("members")} k where k.${mb("conversation")} = v_conv.${cv("id")} and k.${mb("user")} = ${user}))${readsRecord(user)}`;

  const follow = (user: string): string =>
    watchSql(ctx, {
      tenant: `v_msg.${ms("tenant")}`,
      user,
      subjectType: message,
      subjectId: `v_msg.${ms("thread")}::text`,
    });

  const effects = notifications
    ? `
  -- Mentioned users who can read the conversation.
  v_mentioned := array(
    select distinct x from unnest(v_msg.${ms("mentions")}) x
    where x is distinct from v_msg.${ms("author")}
      and ${canRead("x")}
  );
  if v_msg.${ms("mentionScope")} is not null then
    v_mentioned := v_mentioned || array(
      select k.${mb("user")} from ${t("members")} k
      where k.${mb("conversation")} = v_conv.${cv("id")} and k.${mb("notify")} <> 'none'
        and k.${mb("user")} is distinct from v_msg.${ms("author")}
    );
  end if;
  v_mentioned := array(
    select distinct x from unnest(v_mentioned) x
    where not exists (select 1 from ${t("members")} k where k.${mb("conversation")} = v_conv.${cv("id")} and k.${mb("user")} = x and k.${mb("notify")} = 'none')
  );
  if cardinality(v_mentioned) > 0 then
    ${notify("message.mentioned", `,\n      'recipients', to_jsonb(v_mentioned),\n      'watchers', false,\n      'key', ${sqlString(q.e("message.mentioned:"))} || v_msg.${ms("id")}::text`)}
  end if;
  if v_conv.${cv("kind")} in ('dm', 'group_dm') and v_msg.${ms("thread")} is null then
    v_direct := array(
      select k.${mb("user")} from ${t("members")} k
      where k.${mb("conversation")} = v_conv.${cv("id")} and k.${mb("notify")} = 'all'
        and k.${mb("user")} is distinct from v_msg.${ms("author")}
        and not k.${mb("user")} = any (v_mentioned)
    );
    if cardinality(v_direct) > 0 then
      ${notify("message.direct", `,\n      'recipients', to_jsonb(v_direct),\n      'watchers', false,\n      'key', ${sqlString(q.e("message.direct:"))} || v_msg.${ms("id")}::text`)}
    end if;
  end if;
  if v_msg.${ms("thread")} is not null then
    -- The replier and the root's author follow the thread; its followers
    -- hear of the reply, less the members already told above.
    ${follow(`v_msg.${ms("author")}`)}
    ${follow(`(select r.${ms("author")} from ${t("messages")} r where r.${ms("id")} = v_msg.${ms("thread")})`)}
    ${notify("message.replied", `,\n      'recipients', '[]'::jsonb,\n      'exclude', to_jsonb(v_mentioned),\n      'key', ${sqlString(q.e("message.replied:"))} || v_msg.${ms("id")}::text`)}
  end if;`
    : "";

  return `
-- Runs once a message is sent (now or when its schedule comes due): the
-- event, the notifications and the after hook.
create or replace function ${fn("messaging_message_sent")}(message uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_msg ${t("messages")};
  v_conv ${t("conversations")};${notifications ? "\n  v_mentioned uuid[];\n  v_direct uuid[];\n  v_claims text;" : ""}
begin
  select * into v_msg from ${t("messages")} m where m.${ms("id")} = messaging_message_sent.message;
  select * into v_conv from ${t("conversations")} c where c.${cv("id")} = v_msg.${ms("conversation")};
  perform ${fn("index_record_mentions")}(v_msg.${ms("id")});
  ${messageRecord(q, "message.sent", "v_msg", `, 'mentionIds', to_jsonb(v_msg.${ms("mentions")}), 'recordMentions', (select coalesce(jsonb_agg(jsonb_build_object('type', x.${rm("subjectType")}, 'id', x.${rm("subjectId")}) order by x.${rm("subjectType")}, x.${rm("subjectId")}), '[]'::jsonb) from ${t("recordMentions")} x where x.${rm("message")} = v_msg.${ms("id")})`)}${effects}
  ${ctx.hook("after_message_send", [["uuid", `v_msg.${ms("id")}`]])}
end;
$$;
revoke execute on function ${fn("messaging_message_sent")}(uuid) from public, anon, authenticated;`;
}

/** `ctx.record` of a message event over the row variable `row`. */
function messageRecord(
  q: MessagingSql,
  type: string,
  row: string,
  extra = "",
): string {
  const ms = q.cols("messages");
  const cv = q.cols("conversations");

  return q.ctx.record({
    type,
    payload: `jsonb_build_object('organizationId', ${row}.${ms("tenant")}::text, 'conversationId', ${row}.${ms("conversation")}, 'messageId', ${row}.${ms("id")}, 'authorId', ${row}.${ms("author")}, 'threadId', ${row}.${ms("thread")}, 'subjectType', ${sqlString(q.e("message"))}, 'subjectId', ${row}.${ms("id")}::text${extra})
      || coalesce((select jsonb_build_object('conversationKind', c.${cv("kind")}, 'recordType', c.${cv("subjectType")}, 'recordId', c.${cv("subjectId")}) from ${q.t("conversations")} c where c.${cv("id")} = ${row}.${ms("conversation")}), '{}'::jsonb)`,
    subject: `'messages/' || ${row}.${ms("id")}::text`,
    tenant: `${row}.${ms("tenant")}::text`,
    audit: false,
  });
}

/** Messages: send, edit, delete, pin, resolve, list and publish. */
function messageFunctions(q: MessagingSql): string {
  const { ctx, t, fn } = q;
  const cv = q.cols("conversations");
  const ms = q.cols("messages");
  const ed = q.cols("edits");
  const extras = ctx.extraColumns("messages", MESSAGE_RESERVED);
  const message = sqlString(q.e("message"));
  const conversation = sqlString(q.e("conversation"));

  const attachments = ctx.installed("attachments")
    ? ctx.of("attachments")
    : undefined;

  const a = (column: string): string =>
    attachments === undefined ? column : attachments.col("attachments", column);

  const attach =
    attachments === undefined
      ? `
  if cardinality(coalesce(send_message.attachments, '{}')) > 0 then
    ${fail("MESSAGING_ATTACHMENTS_UNAVAILABLE", "install the attachments block to send files", "22023")}
  end if;`
      : `
  -- Files the caller uploaded to the conversation move onto the message.
  if cardinality(coalesce(send_message.attachments, '{}')) > 0 then
    update ${attachments.table("attachments")} a
    set ${a("subjectType")} = ${message}, ${a("subjectId")} = v_id::text
    where a.${a("id")} = any (send_message.attachments)
      and a.${a("tenant")} = v_conv.${cv("tenant")}
      and a.${a("subjectType")} = ${conversation} and a.${a("subjectId")} = v_conv.${cv("id")}::text
      and a.${a("uploadedBy")} = auth.uid()
      and a.${a("status")} <> 'infected';
    get diagnostics v_count = row_count;
    if v_count <> cardinality(array(select distinct x from unnest(send_message.attachments) x)) then
      ${fail("MESSAGING_ATTACHMENT_INVALID", "attach files you uploaded to this conversation", "22023")}
    end if;
  end if;`;

  const anchorFile =
    attachments === undefined
      ? `
    ${fail("MESSAGING_ATTACHMENTS_UNAVAILABLE", "install the attachments block to anchor a message to a file", "22023")}`
      : `
    if not exists (
      select 1 from ${attachments.table("attachments")} a
      where a.${a("id")} = (send_message.attrs -> 'anchor' ->> 'attachmentId')::uuid
        and a.${a("tenant")} = v_conv.${cv("tenant")}
        and a.${a("status")} <> 'infected'
        and ((a.${a("subjectType")} = v_conv.${cv("subjectType")} and a.${a("subjectId")} = v_conv.${cv("subjectId")})
          or (a.${a("subjectType")} = ${message} and exists (
            select 1 from ${t("messages")} m
            where m.${ms("id")}::text = a.${a("subjectId")} and m.${ms("conversation")} = v_conv.${cv("id")})))
    ) then
      ${fail("MESSAGING_ANCHOR_INVALID", "anchor the message to a file on this record or in this conversation", "22023")}
    end if;`;

  const detach =
    attachments === undefined
      ? ""
      : `
  delete from ${attachments.table("attachments")} a
  where a.${a("subjectType")} = ${message} and a.${a("subjectId")} = v_msg.${ms("id")}::text;`;

  const schedule = ctx.installed("jobs")
    ? `
    ${ctx.enqueue(
      q.scheduleQueue,
      `jsonb_build_object('type', 'message.publish', 'messageId', v_id)`,
      `'message.publish:' || v_id::text`,
      {
        delay: `greatest(ceil(extract(epoch from (v_scheduled - now())))::integer, 0)`,
      },
    )}`
    : "";

  const editable = (alias: string): string =>
    q.editWindow === 0
      ? "true"
      : `${alias}.${ms("sentAt")} > now() - interval '${String(q.editWindow)} seconds'`;

  const depth =
    q.threadDepth === 1
      ? `
    -- One level of threads: a reply to a reply joins the root's thread.
    v_parent := coalesce(v_root, v_parent);`
      : "";

  const parse = `${fn("parse_mentions")}(send_message.body)`;
  const rm = q.cols("recordMentions");

  return `
-- The mentions in a body: @[Name](user:<id>) or @[Name](<id>) users,
-- @[Name](subject:<type>/<id>) records, and @channel or @here.
create or replace function ${fn("parse_mentions")}(body text)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_object(
    'users', coalesce((
      select jsonb_agg(distinct lower(m[1]))
      from regexp_matches(parse_mentions.body, '@\\[[^\\]\\n]{1,100}\\]\\((?:user:)?(${UUID})\\)', 'gi') m
    ), '[]'::jsonb),
    'subjects', coalesce((
      select jsonb_agg(distinct jsonb_build_object('type', m[1], 'id', m[2]))
      from regexp_matches(parse_mentions.body, '@\\[[^\\]\\n]{1,100}\\]\\(subject:([a-z][a-z0-9_]{0,62})/([^)\\s]{1,200})\\)', 'g') m
    ), '[]'::jsonb),
    'scope', case
      when parse_mentions.body ~ '(^|[^\\w@])@channel\\M' then 'channel'
      when parse_mentions.body ~ '(^|[^\\w@])@here\\M' then 'here'
    end
  )
$$;
revoke execute on function ${fn("parse_mentions")}(text) from public, anon;
grant execute on function ${fn("parse_mentions")}(text) to authenticated, service_role;

-- Whether a file anchor has a valid shape: an attachmentId, and optionally a
-- page from 1, a region as fractions of the page or frame (x, y, width,
-- height, inside 0 to 1), and a time span in seconds (start from 0, end
-- after start).
create or replace function ${fn("messaging_file_anchor_valid")}(anchor jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select coalesce(
    jsonb_typeof(anchor) = 'object'
    and anchor ->> 'kind' = 'file'
    and coalesce(anchor ->> 'attachmentId', '') ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
    and (anchor -> 'page' is null
      or (jsonb_typeof(anchor -> 'page') = 'number' and (anchor ->> 'page')::numeric >= 1
        and (anchor ->> 'page')::numeric = trunc((anchor ->> 'page')::numeric)))
    and (anchor -> 'region' is null
      or (jsonb_typeof(anchor -> 'region') = 'object'
        and jsonb_typeof(anchor -> 'region' -> 'x') = 'number'
        and jsonb_typeof(anchor -> 'region' -> 'y') = 'number'
        and jsonb_typeof(anchor -> 'region' -> 'width') = 'number'
        and jsonb_typeof(anchor -> 'region' -> 'height') = 'number'
        and (anchor -> 'region' ->> 'x')::numeric >= 0
        and (anchor -> 'region' ->> 'y')::numeric >= 0
        and (anchor -> 'region' ->> 'width')::numeric > 0
        and (anchor -> 'region' ->> 'height')::numeric > 0
        and (anchor -> 'region' ->> 'x')::numeric + (anchor -> 'region' ->> 'width')::numeric <= 1
        and (anchor -> 'region' ->> 'y')::numeric + (anchor -> 'region' ->> 'height')::numeric <= 1))
    and (anchor -> 'start' is null
      or (jsonb_typeof(anchor -> 'start') = 'number' and (anchor ->> 'start')::numeric >= 0))
    and (anchor -> 'end' is null
      or (jsonb_typeof(anchor -> 'start') = 'number' and jsonb_typeof(anchor -> 'end') = 'number'
        and (anchor ->> 'end')::numeric > (anchor ->> 'start')::numeric)),
    false)
$$;
revoke execute on function ${fn("messaging_file_anchor_valid")}(jsonb) from public, anon;
grant execute on function ${fn("messaging_file_anchor_valid")}(jsonb) to authenticated, service_role;

-- Stores the records a sent message mentions, at most ${String(MAX_RECORD_MENTIONS)} of registered
-- subject types, in place of the ones stored before. A deleted or unsent
-- message keeps none.
create or replace function ${fn("index_record_mentions")}(message uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from ${t("recordMentions")} x where x.${rm("message")} = index_record_mentions.message;
  insert into ${t("recordMentions")} (${rm("tenant")}, ${rm("message")}, ${rm("conversation")}, ${rm("subjectType")}, ${rm("subjectId")}, ${rm("createdAt")})
  select m.${ms("tenant")}, m.${ms("id")}, m.${ms("conversation")}, r.subject_type, r.subject_id, m.${ms("sentAt")}
  from ${t("messages")} m
  cross join lateral (
    select s ->> 'type' as subject_type, s ->> 'id' as subject_id
    from jsonb_array_elements(${fn("parse_mentions")}(m.${ms("body")}) -> 'subjects') s
    where s ->> 'type' = any (${ctx.of("subjects").fn("subject_types")}())
    limit ${String(MAX_RECORD_MENTIONS)}
  ) r
  where m.${ms("id")} = index_record_mentions.message
    and m.${ms("sentAt")} is not null and m.${ms("deletedAt")} is null
  on conflict do nothing;
end;
$$;
revoke execute on function ${fn("index_record_mentions")}(uuid) from public, anon, authenticated;

-- The sent messages that mention a record, newest first: before
-- (before, before_id) when given. Each item has the message and its
-- conversation's id, kind, title and record. Runs as the caller, so it lists
-- the messages they read, and nothing when they can't read the record.
create or replace function ${fn("list_record_mentions")}(subject_type text, subject_id text, before timestamptz default null, before_id uuid default null, max_rows integer default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select case when not coalesce(${ctx.of("subjects").fn("can_subject")}(list_record_mentions.subject_type, list_record_mentions.subject_id, 'read'), false)
    then '[]'::jsonb
    else coalesce((
      select jsonb_agg(jsonb_build_object(
        'message', ${fn("messaging_messages_json")}(array[p.message]) -> 0,
        'conversation', jsonb_build_object('id', c.${cv("id")}, 'kind', c.${cv("kind")}, 'title', c.${cv("title")}, 'subject_type', c.${cv("subjectType")}, 'subject_id', c.${cv("subjectId")})
      ) order by p.created_at desc, p.message desc)
      from (
        select x.${rm("message")} as message, x.${rm("conversation")} as conversation, x.${rm("createdAt")} as created_at
        from ${t("recordMentions")} x
        where x.${rm("subjectType")} = list_record_mentions.subject_type and x.${rm("subjectId")} = list_record_mentions.subject_id
          and (list_record_mentions.before is null
            or (x.${rm("createdAt")}, x.${rm("message")}) < (list_record_mentions.before, coalesce(list_record_mentions.before_id, ${MAX_UUID})))
        order by x.${rm("createdAt")} desc, x.${rm("message")} desc
        limit ${pageSize("list_record_mentions.max_rows", 20, 100)}
      ) p
      join ${t("conversations")} c on c.${cv("id")} = p.conversation
    ), '[]'::jsonb)
  end
$$;
${userGrant(`${fn("list_record_mentions")}(text, text, timestamptz, uuid, integer)`)}

-- Sends a message. attrs: parentId (a reply), document (rich text next to
-- body as plain text), anchor (where on the record a top-level message
-- points, such as a text range), mentions (user ids, merged with the body's
-- markup), broadcast (a reply also shown in the conversation), scheduledFor (sends
-- later) and fields (the extra columns). attachments: ids of files the caller
-- uploaded to the conversation. Returns the message.
create or replace function ${fn("send_message")}(conversation uuid, body text, attrs jsonb default '{}', attachments uuid[] default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_conv ${t("conversations")};
  v_id uuid;
  v_parent uuid := nullif(send_message.attrs ->> 'parentId', '')::uuid;
  v_root uuid;
  v_parsed jsonb := ${parse};
  v_mentions uuid[];
  v_scheduled timestamptz := nullif(send_message.attrs ->> 'scheduledFor', '')::timestamptz;
  v_count integer;
begin
  select * into v_conv from ${t("conversations")} c where c.${cv("id")} = send_message.conversation;
  if not found or not ${fn("can_conversation")}(v_conv.${cv("id")}, 'read') then
    ${fail("MESSAGING_NOT_FOUND", "no such conversation you can read", "P0002")}
  end if;${
    q.ctx.installed("inbox")
      ? `
  if v_conv.${cv("kind")} = 'inbox' then
    ${fail("MESSAGING_FORBIDDEN", "write to an inbox conversation through send_inbox_message")}
  end if;`
      : ""
  }
  if v_conv.${cv("access")} = 'tenant' and not ${q.service} and v_conv.${cv("archivedAt")} is null
    and ${q.can(`v_conv.${cv("tenant")}`, "send")} then
    perform ${fn("add_conversation_members")}(v_conv.${cv("id")}, array[auth.uid()]);
  end if;
  if not ${fn("can_conversation")}(v_conv.${cv("id")}, 'send') then
    ${fail("MESSAGING_FORBIDDEN", "not allowed to send messages here")}
  end if;
  if nullif(trim(coalesce(send_message.body, '')), '') is null and cardinality(coalesce(send_message.attachments, '{}')) = 0 then
    ${fail("MESSAGING_BODY_REQUIRED", "a message needs a body or a file", "23502")}
  end if;
  if v_parent is not null then
    select m.${ms("thread")} into v_root from ${t("messages")} m
    where m.${ms("id")} = v_parent and m.${ms("conversation")} = v_conv.${cv("id")}
      and m.${ms("sentAt")} is not null and m.${ms("deletedAt")} is null;
    if not found then
      ${fail("MESSAGING_PARENT_INVALID", "reply to a sent message in the same conversation", "22023")}
    end if;${depth}
  end if;
  if v_parent is null and send_message.attrs -> 'anchor' ->> 'kind' = 'file' then
    if not ${fn("messaging_file_anchor_valid")}(send_message.attrs -> 'anchor') then
      ${fail("MESSAGING_ANCHOR_INVALID", "a file anchor needs an attachmentId, a page from 1, a region inside 0 to 1 and a time span from 0", "22023")}
    end if;${anchorFile}
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
  ${ctx.hook("before_message_send", [
    ["uuid", "send_message.conversation"],
    ["text", "send_message.body"],
    ["jsonb", "send_message.attrs"],
  ])}
  begin
    insert into ${t("messages")} (${ms("tenant")}, ${ms("conversation")}, ${ms("parent")}, ${ms("thread")}, ${ms("author")}, ${ms("body")}, ${ms("document")}, ${ms("anchor")},
      ${ms("mentions")}, ${ms("mentionScope")}, ${ms("broadcast")}, ${ms("scheduledFor")}, ${ms("sentAt")})
    values (v_conv.${cv("tenant")}, v_conv.${cv("id")}, v_parent, case when v_parent is null then null else coalesce(v_root, v_parent) end,
      auth.uid(), coalesce(send_message.body, ''), send_message.attrs -> 'document',
      case when v_parent is null then send_message.attrs -> 'anchor' end, v_mentions,
      case when v_conv.${cv("access")} = 'subject' then null else v_parsed ->> 'scope' end,
      v_parent is not null and coalesce((send_message.attrs ->> 'broadcast')::boolean, false),
      v_scheduled, case when v_scheduled is null then now() end)
    returning ${ms("id")} into v_id;
  exception when check_violation or invalid_text_representation or datetime_field_overflow then
    ${fail("MESSAGING_MESSAGE_INVALID", "a message field has an invalid value", "22023")}
  end;${writeExtraColumns(t("messages"), extras, "(send_message.attrs -> 'fields')", `x.${ms("id")} = v_id`)}${attach}
  if v_scheduled is null then
    perform ${fn("messaging_message_sent")}(v_id);
  else${schedule}
    null;
  end if;
  return ${fn("messaging_messages_json")}(array[v_id]) -> 0;
end;
$$;
${userGrant(`${fn("send_message")}(uuid, text, jsonb, uuid[])`)}

-- Sends the scheduled messages that are due, oldest first, at most max_rows.
-- The jobs queue (options.scheduleQueue) or a cron calls it as the service
-- role. Returns how many it sent.
create or replace function ${fn("publish_due_messages")}(max_rows integer default 100)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_sent integer := 0;
begin
  if not ${q.service} then
    ${fail("MESSAGING_FORBIDDEN", "publish_due_messages runs as the service role")}
  end if;
  for v_id in
    select m.${ms("id")} from ${t("messages")} m
    where m.${ms("sentAt")} is null and m.${ms("deletedAt")} is null and m.${ms("scheduledFor")} <= now()
    order by m.${ms("scheduledFor")}, m.${ms("id")}
    limit ${pageSize("publish_due_messages.max_rows", 100, 1000)}
    for update skip locked
  loop
    update ${t("messages")} m set ${ms("sentAt")} = now() where m.${ms("id")} = v_id;
    perform ${fn("messaging_message_sent")}(v_id);
    v_sent := v_sent + 1;
  end loop;
  return v_sent;
end;
$$;
${serviceGrant(`${fn("publish_due_messages")}(integer)`)}

-- Edits the caller's own message${q.editWindow === 0 ? "" : ` within ${String(q.editWindow)} seconds of sending it`}; the old body goes to
-- message_edits. attrs: document (null removes it), mentions, fields.
create or replace function ${fn("edit_message")}(message uuid, body text, attrs jsonb default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_msg ${t("messages")};
  v_parsed jsonb := ${fn("parse_mentions")}(edit_message.body);
begin
  select * into v_msg from ${t("messages")} m
  where m.${ms("id")} = edit_message.message and m.${ms("author")} = auth.uid() and m.${ms("deletedAt")} is null
    and ${fn("can_conversation")}(m.${ms("conversation")}, 'read');
  if not found then
    ${fail("MESSAGING_NOT_FOUND", "no message of yours has this id", "P0002")}
  end if;
  if v_msg.${ms("sentAt")} is not null and not (${editable("v_msg")}) then
    ${fail("MESSAGING_EDIT_CLOSED", "this message can no longer be edited", "55000")}
  end if;
  if nullif(trim(coalesce(edit_message.body, '')), '') is null then
    ${fail("MESSAGING_BODY_REQUIRED", "a message needs a body", "23502")}
  end if;
  ${ctx.hook("before_message_edit", [
    ["uuid", "edit_message.message"],
    ["text", "edit_message.body"],
  ])}
  insert into ${t("edits")} (${ed("tenant")}, ${ed("message")}, ${ed("body")}, ${ed("document")}, ${ed("editor")})
  values (v_msg.${ms("tenant")}, v_msg.${ms("id")}, v_msg.${ms("body")}, v_msg.${ms("document")}, auth.uid());
  begin
    update ${t("messages")} m set
      ${ms("body")} = edit_message.body,
      ${ms("document")} = case when edit_message.attrs ? 'document' then edit_message.attrs -> 'document' else m.${ms("document")} end,
      ${ms("mentions")} = array(
        select distinct x from (
          select (jsonb_array_elements_text(coalesce(edit_message.attrs -> 'mentions', '[]'::jsonb)))::uuid as x
          union
          select (jsonb_array_elements_text(v_parsed -> 'users'))::uuid
        ) s
      ),
      ${ms("editedAt")} = now()
    where m.${ms("id")} = v_msg.${ms("id")}
    returning * into v_msg;
  exception when check_violation or invalid_text_representation then
    ${fail("MESSAGING_MESSAGE_INVALID", "a message field has an invalid value", "22023")}
  end;${writeExtraColumns(t("messages"), extras, "(edit_message.attrs -> 'fields')", `x.${ms("id")} = v_msg.${ms("id")}`)}
  if v_msg.${ms("sentAt")} is not null then
    perform ${fn("index_record_mentions")}(v_msg.${ms("id")});
    ${messageRecord(q, "message.edited", "v_msg")}
  end if;
  ${ctx.hook("after_message_edit", [["uuid", `v_msg.${ms("id")}`]])}
  return ${fn("messaging_messages_json")}(array[v_msg.${ms("id")}]) -> 0;
end;
$$;
${userGrant(`${fn("edit_message")}(uuid, text, jsonb)`)}

-- Deletes a message: its author or a moderator. It stays as a placeholder
-- (empty body, deleted_at) so its thread keeps its place, and its files go.
create or replace function ${fn("delete_message")}(message uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_msg ${t("messages")};
begin
  select * into v_msg from ${t("messages")} m
  where m.${ms("id")} = delete_message.message and m.${ms("deletedAt")} is null
    and ${fn("can_conversation")}(m.${ms("conversation")}, 'read');
  if not found then
    return false;
  end if;
  if not (${q.service} or v_msg.${ms("author")} = auth.uid() or ${fn("can_conversation")}(v_msg.${ms("conversation")}, 'moderate')) then
    ${fail("MESSAGING_FORBIDDEN", "not allowed to delete this message")}
  end if;
  update ${t("messages")} m set ${ms("body")} = '', ${ms("document")} = null, ${ms("mentions")} = '{}', ${ms("mentionScope")} = null,
    ${ms("pinnedAt")} = null, ${ms("pinnedBy")} = null, ${ms("deletedAt")} = now()
  where m.${ms("id")} = v_msg.${ms("id")}
  returning * into v_msg;
  delete from ${t("edits")} x where x.${ed("message")} = v_msg.${ms("id")};
  delete from ${t("recordMentions")} x where x.${rm("message")} = v_msg.${ms("id")};${detach}
  if v_msg.${ms("sentAt")} is not null then
    ${messageRecord(q, "message.deleted", "v_msg")}
  end if;
  return true;
end;
$$;
${userGrant(`${fn("delete_message")}(uuid)`)}

-- Pins or unpins a message: anyone who may send to the conversation.
create or replace function ${fn("pin_message")}(message uuid, pinned boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_msg ${t("messages")};
begin
  select * into v_msg from ${t("messages")} m
  where m.${ms("id")} = pin_message.message and m.${ms("deletedAt")} is null and m.${ms("sentAt")} is not null;
  if not found or not ${fn("can_conversation")}(v_msg.${ms("conversation")}, 'send') then
    ${fail("MESSAGING_NOT_FOUND", "no such message you can pin", "P0002")}
  end if;
  update ${t("messages")} m
  set ${ms("pinnedAt")} = case when pin_message.pinned then coalesce(m.${ms("pinnedAt")}, now()) end,
    ${ms("pinnedBy")} = case when pin_message.pinned then coalesce(m.${ms("pinnedBy")}, auth.uid()) end
  where m.${ms("id")} = v_msg.${ms("id")}
  returning * into v_msg;
  ${messageRecord(q, "message.pinned", "v_msg", ", 'pinned', pin_message.pinned")}
  return ${fn("messaging_messages_json")}(array[v_msg.${ms("id")}]) -> 0;
end;
$$;
${userGrant(`${fn("pin_message")}(uuid, boolean)`)}

-- Resolves a thread (its root message) or opens it again: the root's author,
-- or anyone who may send to the conversation.
create or replace function ${fn("resolve_message")}(message uuid, resolved boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_msg ${t("messages")};
begin
  select * into v_msg from ${t("messages")} m
  where m.${ms("id")} = resolve_message.message and m.${ms("thread")} is null and m.${ms("deletedAt")} is null and m.${ms("sentAt")} is not null;
  if not found or not ${fn("can_conversation")}(v_msg.${ms("conversation")}, 'send') then
    ${fail("MESSAGING_NOT_FOUND", "no such thread you can resolve", "P0002")}
  end if;
  update ${t("messages")} m
  set ${ms("resolvedAt")} = case when resolve_message.resolved then coalesce(m.${ms("resolvedAt")}, now()) end,
    ${ms("resolvedBy")} = case when resolve_message.resolved then coalesce(m.${ms("resolvedBy")}, auth.uid()) end
  where m.${ms("id")} = v_msg.${ms("id")}
  returning * into v_msg;
  ${messageRecord(q, "message.resolved", "v_msg", ", 'resolved', resolve_message.resolved")}
  return ${fn("messaging_messages_json")}(array[v_msg.${ms("id")}]) -> 0;
end;
$$;
${userGrant(`${fn("resolve_message")}(uuid, boolean)`)}

-- A page of a conversation's top-level messages (and replies sent to it too),
-- oldest first: the newest max_rows before (before, before_id), or with
-- after, the oldest after (after, after_id). Scheduled messages show to their
-- author only, after the sent ones.
create or replace function ${fn("list_messages")}(conversation uuid, after timestamptz default null, after_id uuid default null, before timestamptz default null, before_id uuid default null, max_rows integer default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select ${fn("messaging_messages_json")}(array(
    select p.${ms("id")} from (
      select m.${ms("id")} from ${t("messages")} m
      where m.${ms("conversation")} = list_messages.conversation
        and (m.${ms("thread")} is null or m.${ms("broadcast")})
        and m.${ms("sentAt")} is not null
        and (list_messages.after is null
          or (m.${ms("sentAt")}, m.${ms("id")}) > (list_messages.after, coalesce(list_messages.after_id, '00000000-0000-0000-0000-000000000000'::uuid)))
        and (list_messages.before is null
          or (m.${ms("sentAt")}, m.${ms("id")}) < (list_messages.before, coalesce(list_messages.before_id, ${MAX_UUID})))
      order by
        case when list_messages.after is null then m.${ms("sentAt")} end desc,
        case when list_messages.after is null then m.${ms("id")} end desc,
        m.${ms("sentAt")}, m.${ms("id")}
      limit ${pageSize("list_messages.max_rows", 50, 200)}
    ) p
    union all
    select m.${ms("id")} from ${t("messages")} m
    where m.${ms("conversation")} = list_messages.conversation
      and m.${ms("sentAt")} is null and m.${ms("deletedAt")} is null
      and m.${ms("author")} = auth.uid()
      and list_messages.after is null and list_messages.before is null
  ))
$$;
${userGrant(`${fn("list_messages")}(uuid, timestamptz, uuid, timestamptz, uuid, integer)`)}

-- A thread's replies, oldest first, after (after, after_id) when given.
create or replace function ${fn("list_replies")}(message uuid, after timestamptz default null, after_id uuid default null, max_rows integer default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select ${fn("messaging_messages_json")}(array(
    select m.${ms("id")} from ${t("messages")} m
    where m.${ms("thread")} = list_replies.message
      and (m.${ms("sentAt")} is not null or m.${ms("author")} = auth.uid())
      and (list_replies.after is null
        or (m.${ms("sentAt")}, m.${ms("id")}) > (list_replies.after, coalesce(list_replies.after_id, '00000000-0000-0000-0000-000000000000'::uuid)))
    order by m.${ms("sentAt")} nulls last, m.${ms("id")}
    limit ${pageSize("list_replies.max_rows", 100, 500)}
  ))
$$;
${userGrant(`${fn("list_replies")}(uuid, timestamptz, uuid, integer)`)}

-- The top-level messages anchored to a file, oldest first: the comments on
-- its pages, regions and moments. Only the conversations the caller can read.
create or replace function ${fn("list_file_anchors")}(attachment uuid, max_rows integer default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select ${fn("messaging_messages_json")}(array(
    select m.${ms("id")} from ${t("messages")} m
    where m.${ms("anchor")} ->> 'kind' = 'file'
      and m.${ms("anchor")} ->> 'attachmentId' = list_file_anchors.attachment::text
      and m.${ms("sentAt")} is not null and m.${ms("deletedAt")} is null
    order by m.${ms("sentAt")}, m.${ms("id")}
    limit ${pageSize("list_file_anchors.max_rows", 100, 500)}
  ))
$$;
${userGrant(`${fn("list_file_anchors")}(uuid, integer)`)}

-- One message the caller can read, or null: for a Realtime ping's id.
create or replace function ${fn("get_message")}(message uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select ${fn("messaging_messages_json")}(array[get_message.message]) -> 0
$$;
${userGrant(`${fn("get_message")}(uuid)`)}

-- A message's earlier versions, newest first.
create or replace function ${fn("list_message_edits")}(message uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.${ed("editedAt")} desc), '[]'::jsonb)
  from ${t("edits")} x where x.${ed("message")} = list_message_edits.message
$$;
${userGrant(`${fn("list_message_edits")}(uuid)`)}

-- Pinned messages of a conversation, latest pin first.
create or replace function ${fn("list_pinned_messages")}(conversation uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select ${fn("messaging_messages_json")}(array(
    select m.${ms("id")} from ${t("messages")} m
    where m.${ms("conversation")} = list_pinned_messages.conversation and m.${ms("pinnedAt")} is not null
    order by m.${ms("pinnedAt")} desc limit 100
  ))
$$;
${userGrant(`${fn("list_pinned_messages")}(uuid)`)}
`;
}

/** Every messaging function. */
export function messagingFunctions(q: MessagingSql): string {
  return `${messagesJson(q)}
${sentEffects(q)}
${conversationFunctions(q)}
${messageFunctions(q)}
${summaryFunctions(q)}`;
}
