import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlNames,
} from "../context.ts";
import type { BlockContributes } from "../contributions.ts";
import type { BlockSqlDefinition, BlockSqlUpgrade } from "../module-types.ts";

import { isRecord } from "../../core/guards.ts";
import { sqlIdent, sqlString } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import {
  SERVICE_CALLER,
  schemaPreamble,
  pageSize,
  revokeTable,
  fail,
  serviceGrant,
  userGrant,
  quotedTable,
  readLine,
} from "../shared.ts";
import {
  subjectCascades,
  subjectsOption,
  subjectTypeGuard,
} from "../subjects.ts";
import { followersSql, watchSql } from "../watch-sql.ts";
import { messagingSql } from "./messaging-names.ts";
import { messagingTableDdl } from "./messaging-tables.ts";
import { appUniqueIndex } from "./over-app.ts";
import { myWorkTenant } from "./subjects.ts";

const NAMES: BlockSqlNames = {
  hooks: [
    "before_comment_create",
    "after_comment_create",
    "before_comment_assign",
    "after_comment_assign",
  ],
  options: ["follow", "mentionGroups", "notify"],
  tables: {
    tasks: {
      name: "comment_tasks",
      app: {},
      lifecycle: { tenant: "tenant" },
      columns: {
        message: "message_id",
        tenant: "organization_id",
        task: "task_id",
        createdBy: "created_by",
        createdAt: "created_at",
      },
      optional: ["createdBy", "createdAt"],
    },
  },
};

/** Sorts after every uuid, so `after` without `after_id` means strictly later. */
const MAX_UUID = "'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid";

interface MentionGroups {
  readonly table: string;
  readonly group: string;
  readonly member: string;
  readonly tenant?: string;
}

const MENTION_GROUP_KEYS = new Set(["table", "group", "member", "tenant"]);

function mentionGroupsOf(ctx: BlockSqlContext): MentionGroups | undefined {
  const option = ctx.option("mentionGroups");

  if (option === undefined) {
    return undefined;
  }

  const where = "blocks.comments.options.mentionGroups";

  if (!isRecord(option)) {
    throw new TypeError(`${where} must be { table, group, member, tenant? }`);
  }

  for (const key of Object.keys(option)) {
    if (!MENTION_GROUP_KEYS.has(key)) {
      throw new TypeError(
        `${where}.${key} is not an option. Options: table, group, member, tenant`,
      );
    }
  }

  const text = (key: string): string | undefined => {
    const value = option[key];

    if (value === undefined) {
      return undefined;
    }

    if (typeof value !== "string" || value.length === 0) {
      throw new TypeError(`${where}.${key} must be a non-empty string`);
    }

    return value;
  };

  const table = text("table");
  const group = text("group");
  const member = text("member");

  if (table === undefined || group === undefined || member === undefined) {
    throw new TypeError(`${where} needs table, group and member`);
  }

  const tenant = text("tenant");

  return { table, group, member, ...(tenant !== undefined && { tenant }) };
}

/** A column name as a JSON key of `to_jsonb(row)`. */
const key = (column: string): string => sqlString(column.replaceAll('"', ""));

/**
 * The statements after a comment is sent: its author and the members it
 * mentions follow the record, and the record's followers hear of it, less the
 * ones the message's own notifications reached. Empty without notifications, or
 * with neither `follow` nor `notify`.
 */
function afterSend(ctx: BlockSqlContext): string {
  if (!ctx.installed("notifications")) {
    return "";
  }

  const m = ctx.of("messaging");
  const ms = (column: string): string => m.col("messages", column);
  const cv = (column: string): string => m.col("conversations", column);
  const fn = (name: string): string => ctx.fn(name);

  // Mentions keep group ids next to user ids; only tenant readers follow.
  const readers = m.scope.canUser(
    "x",
    `v_msg.${ms("tenant")}`,
    messagingSql(m).key("read"),
  );

  const follow = ctx.flag("follow", true)
    ? watchSql(ctx, {
        tenant: `v_conv.${cv("tenant")}`,
        user: "v_user",
        subjectType: `v_conv.${cv("subjectType")}`,
        subjectId: `v_conv.${cv("subjectId")}`,
      })
    : "";

  const notify = ctx.flag("notify", true)
    ? `if ${followersSql(ctx, {
        tenant: `v_conv.${cv("tenant")}`,
        subjectType: `v_conv.${cv("subjectType")}`,
        subjectId: `v_conv.${cv("subjectId")}`,
        exclude: `array[v_msg.${ms("author")}] || v_msg.${ms("mentions")}`,
      })} then
    ${ctx.notify(
      `jsonb_build_object(
      'type', 'comment.posted',
      'tenant', v_msg.${ms("tenant")},
      'actor', v_msg.${ms("author")},
      'subject_type', v_conv.${cv("subjectType")},
      'subject_id', v_conv.${cv("subjectId")},
      'subject_label', ${ctx.of("subjects").fn("subject_title")}(v_conv.${cv("subjectType")}, v_conv.${cv("subjectId")}),
      'summary', left(v_msg.${ms("body")}, 140),
      'recipients', '[]'::jsonb,
      'exclude', to_jsonb(v_msg.${ms("mentions")}),
      'key', 'comment.posted:' || v_msg.${ms("id")}::text,
      'data', jsonb_build_object('messageId', v_msg.${ms("id")}, 'conversationId', v_msg.${ms("conversation")})
    )`,
      { indent: "    " },
    )}
  end if;`
    : "";

  if (follow === "" && notify === "") {
    return "";
  }

  return `
-- After create_comment sends: the author and the mentioned members follow
-- the record (participating; a level they chose stays), and its followers
-- hear of the comment. Only the author of a sent message on a record calls
-- it with effect.
create or replace function ${fn("comment_sent")}(message uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_msg record;
  v_conv record;
  v_user uuid;${notify === "" ? "" : "\n  v_claims text;"}
begin
  select * into v_msg from ${m.table("messages")} x
  where x.${ms("id")} = comment_sent.message and x.${ms("author")} = auth.uid()
    and x.${ms("sentAt")} is not null and x.${ms("deletedAt")} is null;
  if not found then
    return;
  end if;
  select * into v_conv from ${m.table("conversations")} c
  where c.${cv("id")} = v_msg.${ms("conversation")} and c.${cv("kind")} = 'subject';
  if not found then
    return;
  end if;${
    follow === ""
      ? ""
      : `
  foreach v_user in array array(select distinct x from unnest(array[v_msg.${ms("author")}] || v_msg.${ms("mentions")}) x where x = v_msg.${ms("author")} or ${readers}) loop
    ${follow}
  end loop;`
  }
  ${notify}
end;
$$;
${userGrant(`${fn("comment_sent")}(uuid)`)}`;
}

/** `assign_comment`, with the tasks module. */
function assignSql(ctx: BlockSqlContext): string {
  if (!ctx.installed("tasks")) {
    return "";
  }

  const m = ctx.of("messaging");
  const ms = (column: string): string => m.col("messages", column);
  const k = (column: string): string => ctx.col("tasks", column);
  const fn = (name: string): string => ctx.fn(name);
  const create = ctx.of("tasks").fn("create_task");

  return `
-- Turns a comment into a work item: the title (attrs.title, else the
-- comment's first 120 characters), its body, and assignee when given; the
-- other attrs go to create_task. A comment links to one work item;
-- assigning it again returns that one's id.
create or replace function ${fn("assign_comment")}(message uuid, assignee uuid default null, attrs jsonb default '{}')
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_msg record;
  v_task uuid;
begin
  select * into v_msg from ${m.table("messages")} x
  where x.${ms("id")} = assign_comment.message and x.${ms("sentAt")} is not null and x.${ms("deletedAt")} is null;
  if not found then
    ${fail("COMMENT_NOT_FOUND", "no comment you can read has this id", "P0002")}
  end if;
  select t.${k("task")} into v_task from ${ctx.table("tasks")} t where t.${k("message")} = v_msg.${ms("id")};
  if found then
    return v_task;
  end if;
  ${ctx.hook("before_comment_assign", [
    ["uuid", "assign_comment.message"],
    ["uuid", "assign_comment.assignee"],
  ])}
  v_task := (${create}(
    v_msg.${ms("tenant")},
    (coalesce(assign_comment.attrs, '{}') - 'title') || jsonb_build_object(
      'title', coalesce(nullif(trim(assign_comment.attrs ->> 'title'), ''), left(v_msg.${ms("body")}, 120)),
      'body', coalesce(assign_comment.attrs ->> 'body', v_msg.${ms("body")})
    ),
    case when assign_comment.assignee is null then '{}'::uuid[] else array[assign_comment.assignee] end
  ) ->> 'id')::uuid;
  insert into ${ctx.table("tasks")} (${k("message")}, ${k("tenant")}, ${k("task")})
  values (v_msg.${ms("id")}, v_msg.${ms("tenant")}, v_task);
  ${ctx.hook("after_comment_assign", [["uuid", "v_task"]])}
  return v_task;
end;
$$;
${userGrant(`${fn("assign_comment")}(uuid, uuid, jsonb)`)}`;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const id = ctx.idType;
  const m = ctx.of("messaging");
  const ms = (column: string): string => m.col("messages", column);
  const cv = (column: string): string => m.col("conversations", column);
  const k = (column: string): string => ctx.col("tasks", column);
  const fn = (name: string): string => ctx.fn(name);
  const tasks = ctx.table("tasks");
  const groups = mentionGroupsOf(ctx);
  const anchors = m.has("messages", "anchor");

  // A column definition, left out when the app maps the column to null.
  const column = (
    logical: string,
    definition: (name: string) => string,
  ): string =>
    ctx.has("tasks", logical) ? `,\n  ${definition(k(logical))}` : "";

  const expand =
    groups === undefined
      ? "select x from unnest(v_raw) x"
      : `select x from unnest(v_raw) x
    union select g.${sqlIdent(groups.member)} from ${quotedTable(groups.table)} g where g.${sqlIdent(groups.group)} = any (v_raw)${groups.tenant === undefined ? "" : ` and g.${sqlIdent(groups.tenant)} = create_comment.tenant`}`;

  const sent = afterSend(ctx);

  return `${schemaPreamble(ctx)}
-- Comments are a record's conversation (kind subject) on the messaging core:
-- whoever reads the record reads its comments. These functions open it,
-- expand mention groups, list a record's thread flat with its record, and
-- copy it; edits, deletes, pins, resolving and read markers go through the
-- messaging functions (edit_message, delete_message, pin_message,
-- resolve_message, mark_read). Every function is PL/pgSQL because the
-- messaging tables come later in the schema.

-- The work item a comment was turned into (assign_comment).
create table if not exists ${tasks} (
  ${k("message")} uuid primary key,
  ${k("tenant")} ${ctx.scope.column()},
  ${k("task")} uuid not null${column("createdBy", (name) => `${name} uuid default auth.uid()`)}${column("createdAt", (name) => `${name} timestamptz not null default now()`)}
);${appUniqueIndex(ctx, "tasks", ["message"])}
create index if not exists ${ctx.naming.rename("comment_tasks_task_idx")} on ${tasks} (${k("task")});
alter table ${tasks} enable row level security;${ctx.appOwned.includes("tasks") ? "" : `\n${revokeTable(tasks)}`}
grant select on ${tasks} to authenticated;
grant insert (${[k("message"), k("tenant"), k("task")].join(", ")}) on ${tasks} to authenticated;
grant all on ${tasks} to service_role;

-- Whether the caller reads a message in this tenant: the messages policy
-- decides.
drop function if exists ${fn("comment_message_readable")}(uuid);
create or replace function ${fn("comment_message_readable")}(message uuid, tenant uuid)
returns boolean
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  return exists (
    select 1 from ${m.table("messages")} x
    where x.${ms("id")} = comment_message_readable.message and x.${ms("tenant")} = comment_message_readable.tenant
  );
end;
$$;
${userGrant(`${fn("comment_message_readable")}(uuid, uuid)`)}

${renderPolicy(makePolicy({ table: tasks, name: sqlIdent(`${ctx.tableName("tasks").name}_read`), command: "select", roles: ["authenticated"], using: `${fn("comment_message_readable")}(${k("message")}, ${k("tenant")})` }), { drop: true, target: tasks })}
${renderPolicy(makePolicy({ table: tasks, name: sqlIdent(`${ctx.tableName("tasks").name}_insert`), command: "insert", roles: ["authenticated"], check: `${ctx.has("tasks", "createdBy") ? `${k("createdBy")} = (select auth.uid()) and ` : ""}${fn("comment_message_readable")}(${k("message")}, ${k("tenant")})` }), { drop: true, target: tasks })}

-- A record's conversation, or null before its first comment.
create or replace function ${fn("comment_conversation")}(tenant ${id}, subject_type text, subject_id text)
returns uuid
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_id uuid;
begin
  select c.${cv("id")} into v_id from ${m.table("conversations")} c
  where c.${cv("tenant")} = comment_conversation.tenant and c.${cv("kind")} = 'subject'
    and c.${cv("subjectType")} = comment_conversation.subject_type and c.${cv("subjectId")} = comment_conversation.subject_id;
  return v_id;
end;
$$;
${userGrant(`${fn("comment_conversation")}(${id}, text, text)`)}

-- Messages as comments: each with its record and the work item it became.
create or replace function ${fn("comments_json")}(ids uuid[])
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  return (
    select coalesce(jsonb_agg(e.row || jsonb_build_object(
      'subject_type', c.${cv("subjectType")},
      'subject_id', c.${cv("subjectId")},
      'task_id', t.${k("task")}
    ) order by e.n), '[]'::jsonb)
    from jsonb_array_elements(${m.fn("messaging_messages_json")}(comments_json.ids)) with ordinality e(row, n)
    join ${m.table("conversations")} c on c.${cv("id")} = (e.row ->> ${key(ms("conversation"))})::uuid
    left join ${tasks} t on t.${k("message")} = (e.row ->> ${key(ms("id"))})::uuid
  );
end;
$$;
${userGrant(`${fn("comments_json")}(uuid[])`)}

-- One comment the caller reads, or null.
create or replace function ${fn("get_comment")}(message uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  return ${fn("comments_json")}(array[get_comment.message]) -> 0;
end;
$$;
${userGrant(`${fn("get_comment")}(uuid)`)}

-- Comments on a record. attrs: parentId (a reply; one level, so a reply to
-- a reply joins the root), document, anchor (where on the record it points),
-- mentions (user ids${groups === undefined ? "" : " or mention groups"}) and fields (the messaging extra
-- columns). attachments: files the caller uploaded to the conversation.
drop function if exists ${fn("create_comment")}(${id}, text, text, text, uuid[], uuid, jsonb);
create or replace function ${fn("create_comment")}(
  tenant ${id},
  subject_type text,
  subject_id text,
  body text,
  attrs jsonb default '{}',
  attachments uuid[] default '{}'
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_conv uuid;
  v_raw uuid[];
  v_mentions uuid[];
  v_msg jsonb;
begin${subjectTypeGuard(ctx, "create_comment.subject_type", "COMMENT_SUBJECT_UNSUPPORTED", "  ")}
  ${ctx.hook("before_comment_create", [
    [id, "create_comment.tenant"],
    ["text", "create_comment.subject_type"],
    ["text", "create_comment.subject_id"],
    ["text", "create_comment.body"],
  ])}
  v_conv := (${m.fn("open_conversation")}(
    create_comment.tenant,
    'subject',
    jsonb_build_object('subjectType', create_comment.subject_type, 'subjectId', create_comment.subject_id),
    '{}'::uuid[]
  ) ->> 'id')::uuid;
  v_raw := array(
    select (jsonb_array_elements_text(coalesce(create_comment.attrs -> 'mentions', '[]'::jsonb)))::uuid
  );
  v_mentions := array(select distinct e.x from (
    ${expand}
  ) e(x) where e.x is not null);
  v_msg := ${m.fn("send_message")}(
    v_conv,
    create_comment.body,
    (coalesce(create_comment.attrs, '{}') - 'mentions' - 'broadcast' - 'scheduledFor') || jsonb_build_object('mentions', to_jsonb(v_mentions)),
    coalesce(create_comment.attachments, '{}')
  );${sent === "" ? "" : `\n  perform ${fn("comment_sent")}((v_msg ->> 'id')::uuid);`}
  ${ctx.hook("after_comment_create", [["uuid", "(v_msg ->> 'id')::uuid"]])}
  return ${fn("comments_json")}(array[(v_msg ->> 'id')::uuid]) -> 0;
end;
$$;
${userGrant(`${fn("create_comment")}(${id}, text, text, text, jsonb, uuid[])`)}
${sent}

-- A record's comments and replies in one list, oldest first; deleted ones
-- stay as placeholders so replies keep their parent, unless include_deleted
-- is false. Page with after and after_id (the last comment's sent_at and id)
-- or skip (an offset).
drop function if exists ${fn("list_comments")}(${id}, text, text, timestamptz, integer, integer, uuid);
create or replace function ${fn("list_comments")}(
  tenant ${id},
  subject_type text,
  subject_id text,
  after timestamptz default null,
  max_rows integer default 100,
  skip integer default 0,
  after_id uuid default null,
  include_deleted boolean default true
)
returns jsonb
language plpgsql
${ctx.readVolatility()}
security invoker
set search_path = ''
as $$
declare
  v_conv uuid := ${fn("comment_conversation")}(list_comments.tenant, list_comments.subject_type, list_comments.subject_id);
begin
  if v_conv is null then
    return '[]'::jsonb;
  end if;${readLine(ctx.read("list_comments.subject_type", "list_comments.subject_id", "list_comments"))}
  return ${fn("comments_json")}(array(
    select x.${ms("id")} from ${m.table("messages")} x
    where x.${ms("conversation")} = v_conv and x.${ms("sentAt")} is not null
      and (coalesce(list_comments.include_deleted, true) or x.${ms("deletedAt")} is null)
      and (list_comments.after is null
        or (x.${ms("sentAt")}, x.${ms("id")}) > (list_comments.after, coalesce(list_comments.after_id, ${MAX_UUID})))
    order by x.${ms("sentAt")}, x.${ms("id")}
    limit ${pageSize("list_comments.max_rows", 100, 500)}
    offset greatest(coalesce(list_comments.skip, 0), 0)
  ));
end;
$$;
${userGrant(`${fn("list_comments")}(${id}, text, text, timestamptz, integer, integer, uuid, boolean)`)}

-- The top-level comments anchored to a file, oldest first: on its pages,
-- regions and moments, on any record the caller can read.
create or replace function ${fn("list_file_comments")}(attachment uuid, max_rows integer default 100)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  return ${fn("comments_json")}(array(
    select x.${ms("id")} from ${m.table("messages")} x
    join ${m.table("conversations")} c on c.${cv("id")} = x.${ms("conversation")} and c.${cv("kind")} = 'subject'
    where ${
      anchors
        ? `x.${ms("anchor")} ->> 'kind' = 'file'
      and x.${ms("anchor")} ->> 'attachmentId' = list_file_comments.attachment::text`
        : "false"
    }
      and x.${ms("sentAt")} is not null and x.${ms("deletedAt")} is null
    order by x.${ms("sentAt")}, x.${ms("id")}
    limit ${pageSize("list_file_comments.max_rows", 100, 500)}
  ));
end;
$$;
${userGrant(`${fn("list_file_comments")}(uuid, integer)`)}

-- Comments per record the caller can read, for counters in a list:
-- { subject_id: count }, deleted ones left out.
create or replace function ${fn("comment_counts")}(tenant ${id}, subject_type text, subject_ids text[])
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  return (
    select coalesce(jsonb_object_agg(s.subject_id, s.n), '{}'::jsonb)
    from (
      select c.${cv("subjectId")} as subject_id, count(*) as n
      from ${m.table("conversations")} c
      join ${m.table("messages")} x on x.${ms("conversation")} = c.${cv("id")}
      where c.${cv("tenant")} = comment_counts.tenant and c.${cv("kind")} = 'subject'
        and c.${cv("subjectType")} = comment_counts.subject_type
        and c.${cv("subjectId")} = any (comment_counts.subject_ids)
        and x.${ms("sentAt")} is not null and x.${ms("deletedAt")} is null
      group by 1
    ) s
  );
end;
$$;
${userGrant(`${fn("comment_counts")}(${id}, text, text[])`)}

-- Copies a record's comments to another record in the same tenant (a quote
-- duplicated into an invoice, say), keeping authors, times and replies.
-- Service role only: call it from the code that duplicates the record,
-- after it checked the caller may read both.
create or replace function ${fn("copy_comments")}(
  tenant ${id},
  from_type text,
  from_id text,
  to_type text,
  to_id text
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_from uuid;
  v_to uuid;
  v_copied integer;
begin
  if not (${SERVICE_CALLER}) then
    ${fail("COMMENT_FORBIDDEN", "Only the service role copies comments")}
  end if;
  select c.${cv("id")} into v_from from ${m.table("conversations")} c
  where c.${cv("tenant")} = copy_comments.tenant and c.${cv("kind")} = 'subject'
    and c.${cv("subjectType")} = copy_comments.from_type and c.${cv("subjectId")} = copy_comments.from_id;
  if v_from is null then
    return 0;
  end if;
  insert into ${m.table("conversations")} (${cv("tenant")}, ${cv("kind")}, ${cv("access")}, ${cv("subjectType")}, ${cv("subjectId")})
  values (copy_comments.tenant, 'subject', 'subject', copy_comments.to_type, copy_comments.to_id)
  on conflict do nothing;
  select c.${cv("id")} into v_to from ${m.table("conversations")} c
  where c.${cv("tenant")} = copy_comments.tenant and c.${cv("kind")} = 'subject'
    and c.${cv("subjectType")} = copy_comments.to_type and c.${cv("subjectId")} = copy_comments.to_id;
  with copies as materialized (
    select y.${ms("id")} as old_id, gen_random_uuid() as new_id
    from ${m.table("messages")} y
    where y.${ms("conversation")} = v_from and y.${ms("sentAt")} is not null
  ), inserted as (
    insert into ${m.table("messages")} (${[ms("id"), ms("tenant"), ms("conversation"), ms("parent"), ms("thread"), ms("author"), ms("body"), ms("document"), ...(anchors ? [ms("anchor")] : []), ms("mentions"), ms("replyCount"), ms("lastReplyAt"), ms("replyUsers"), ms("sentAt"), ms("editedAt"), ms("deletedAt"), ms("createdAt")].join(", ")})
    select n.new_id, y.${ms("tenant")}, v_to, p.new_id, r.new_id, y.${ms("author")},
      y.${ms("body")}, y.${ms("document")}, ${anchors ? `y.${ms("anchor")}, ` : ""}y.${ms("mentions")}, y.${ms("replyCount")}, y.${ms("lastReplyAt")}, y.${ms("replyUsers")}, y.${ms("sentAt")}, y.${ms("editedAt")}, y.${ms("deletedAt")}, y.${ms("createdAt")}
    from ${m.table("messages")} y
    join copies n on n.old_id = y.${ms("id")}
    left join copies p on p.old_id = y.${ms("parent")}
    left join copies r on r.old_id = y.${ms("thread")}
    order by y.${ms("sentAt")}, y.${ms("id")}
    returning 1
  )
  select count(*)::integer into v_copied from inserted;
  return v_copied;
end;
$$;
${serviceGrant(`${fn("copy_comments")}(${id}, text, text, text, text)`)}
${assignSql(ctx)}${subjectCascades(
    ctx,
    subjectsOption(ctx, [], { registryOnly: true }),
    `delete from ${m.table("conversations")} c where c.${cv("kind")} = 'subject' and c.${cv("subjectType")} = v_type and c.${cv("subjectId")} = v_id and (v_tenant is null or c.${cv("tenant")}::text = v_tenant);`,
    { tenant: true },
  )}`;
}

function contract(ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "comment_conversation",
      args: ["{id}", "text", "text"],
      returns: "uuid",
    },
    { name: "get_comment", args: ["uuid"], returns: "jsonb" },
    {
      name: "create_comment",
      args: ["{id}", "text", "text", "text", "jsonb", "uuid[]"],
      returns: "jsonb",
    },
    {
      name: "list_comments",
      args: [
        "{id}",
        "text",
        "text",
        "timestamp with time zone",
        "integer",
        "integer",
        "uuid",
        "boolean",
      ],
      returns: "jsonb",
    },
    {
      name: "comment_counts",
      args: ["{id}", "text", "text[]"],
      returns: "jsonb",
    },
    {
      name: "copy_comments",
      args: ["{id}", "text", "text", "text", "text"],
      returns: "integer",
    },
    ...(ctx.installed("tasks")
      ? [
          {
            name: "assign_comment",
            args: ["uuid", "uuid", "jsonb"],
            returns: "uuid",
          },
        ]
      : []),
  ];
}

/** Version 7 kept comments in their own table; version 8 moves them. */
const TO_MESSAGING: BlockSqlUpgrade = {
  from: 7,
  description:
    "Comments move onto the messaging core: each record's comments become its subject conversation, comments become messages with the same ids, reactions and files on a comment move to the message, and the comments table and its functions go. The activity feed moves to the activity module with its table.",
  sql: (ctx) => {
    const m = ctx.of("messaging");
    const ms = (column: string): string => m.col("messages", column);
    const cv = (column: string): string => m.col("conversations", column);
    const msg = m.table("messages");
    const conv = m.table("conversations");
    const old = `${ctx.schema}.comments`;
    const id = ctx.idType;
    const fn = (name: string): string => ctx.fn(name);

    const moves = (["reactions", "attachments"] as const).flatMap((module) => {
      if (!ctx.installed(module)) {
        return [];
      }

      const other = ctx.of(module);
      const table = module === "reactions" ? "reactions" : "attachments";
      const target = other.table(table);
      const type = other.col(table, "subjectType");

      return [
        `  if to_regclass(${sqlString(target)}) is not null then
    update ${target} x set ${type} = 'message' where x.${type} = 'comment';
  end if;`,
      ];
    });

    const base = [
      "id",
      "organization_id",
      "subject_type",
      "subject_id",
      "author_id",
      "body",
      "document",
      "mentions",
      "parent_id",
      "created_at",
      "edited_at",
      "deleted_at",
    ];

    return `-- The messaging tables, so the comments can move before the module files run.
${messagingTableDdl(messagingSql(m))}

do $$
declare
  v_column text;
begin
  if to_regclass(${sqlString(old)}) is null then
    return;
  end if;
  insert into ${conv} (${[cv("tenant"), cv("kind"), cv("access"), cv("subjectType"), cv("subjectId"), cv("createdBy"), cv("lastMessageAt"), cv("createdAt")].join(", ")})
  select x.organization_id, 'subject', 'subject', x.subject_type, x.subject_id,
    (array_agg(x.author_id order by x.created_at, x.id))[1],
    max(x.created_at) filter (where x.deleted_at is null), min(x.created_at)
  from ${old} x
  group by x.organization_id, x.subject_type, x.subject_id
  on conflict do nothing;
  with recursive tree as (
    select c.id, c.id as root from ${old} c where c.parent_id is null
    union all
    select c.id, t.root from ${old} c join tree t on c.parent_id = t.id
  )
  insert into ${msg} (${[ms("id"), ms("tenant"), ms("conversation"), ms("parent"), ms("thread"), ms("author"), ms("body"), ms("document"), ms("mentions"), ms("sentAt"), ms("editedAt"), ms("deletedAt"), ms("createdAt")].join(", ")})
  select x.id, x.organization_id, v.${cv("id")}, x.parent_id, case when x.parent_id is null then null else t.root end,
    x.author_id, x.body, x.document, x.mentions, x.created_at, x.edited_at, x.deleted_at, x.created_at
  from ${old} x
  join tree t on t.id = x.id
  join ${conv} v on v.${cv("tenant")} = x.organization_id and v.${cv("kind")} = 'subject'
    and v.${cv("subjectType")} = x.subject_type and v.${cv("subjectId")} = x.subject_id
  order by x.created_at, x.id
  on conflict do nothing;
  update ${msg} r set
    ${ms("replyCount")} = (select count(*) from ${msg} x where x.${ms("thread")} = r.${ms("id")} and x.${ms("deletedAt")} is null),
    ${ms("lastReplyAt")} = (select max(x.${ms("sentAt")}) from ${msg} x where x.${ms("thread")} = r.${ms("id")} and x.${ms("deletedAt")} is null),
    ${ms("replyUsers")} = array(
      select y.u from (
        select x.${ms("author")} as u, min(x.${ms("sentAt")}) as first
        from ${msg} x
        where x.${ms("thread")} = r.${ms("id")} and x.${ms("deletedAt")} is null and x.${ms("author")} is not null
        group by x.${ms("author")}
      ) y order by y.first limit 3
    )
  where r.${ms("id")} in (select c.parent_id from ${old} c where c.parent_id is not null);
  -- Extra columns the comments and the messages share by name.
  for v_column in
    select a.attname from pg_attribute a
    where a.attrelid = ${sqlString(old)}::regclass and a.attnum > 0 and not a.attisdropped
      and not a.attname = any (${sqlString(`{${base.join(",")}}`)}::text[])
      and exists (
        select 1 from pg_attribute b
        where b.attrelid = ${sqlString(msg)}::regclass and b.attname = a.attname and not b.attisdropped
      )
  loop
    execute format('update %s m set %I = c.%I from %s c where c.id = m.${ms("id").replaceAll('"', "")}', ${sqlString(msg)}, v_column, v_column, ${sqlString(old)});
  end loop;
${moves.join("\n")}
  drop table ${old} cascade;
end;
$$;
drop function if exists ${fn("create_comment")}(${id}, text, text, text, uuid[], uuid, jsonb);
drop function if exists ${fn("create_comment")}(${id}, text, text, text, uuid[], uuid, jsonb, jsonb);
drop function if exists ${fn("edit_comment")}(uuid, text, uuid[], jsonb, boolean);
drop function if exists ${fn("edit_comment")}(uuid, text, uuid[], jsonb, boolean, jsonb);
drop function if exists ${fn("delete_comment")}(uuid);
drop function if exists ${fn("comment_subject_readable")}(text, text, ${id});
drop function if exists ${fn("comment_authors")}(uuid[]);
drop function if exists ${fn("comments_before_write")}();
drop function if exists ${fn("comments_after_write")}();`;
  },
};

const CONTRIBUTES: BlockContributes = {
  subjects: (own) => {
    const messaging = own.of("messaging");

    if (messaging.mode === "custom") {
      return [];
    }

    const m = (column: string): string =>
      `m.${messaging.col("messages", column)}`;

    const c = (column: string): string =>
      `c.${messaging.col("conversations", column)}`;

    return [
      {
        summary: {
          name: "comments",
          from: `${messaging.table("messages")} x
      join ${messaging.table("conversations")} c on c.${messaging.col("conversations", "id")} = x.${messaging.col("messages", "conversation")}
        and c.${messaging.col("conversations", "kind")} = 'subject'`,
          subjectType: `c.${messaging.col("conversations", "subjectType")}`,
          subjectId: `c.${messaging.col("conversations", "subjectId")}`,
          latest: `x.${messaging.col("messages", "sentAt")}`,
          live: `x.${messaging.col("messages", "sentAt")} is not null and x.${messaging.col("messages", "deletedAt")} is null`,
          readAt: `(select ${messaging.fn("conversation_read_at")}(c.${messaging.col("conversations", "id")}) from ${messaging.table("conversations")} c
        where c.${messaging.col("conversations", "kind")} = 'subject'
          and c.${messaging.col("conversations", "subjectType")} = record_summary.subject_type
          and c.${messaging.col("conversations", "subjectId")} = record_summary.subject_id)`,
        },
        work: `select 'mention'::text, ${c("subjectType")}::text, ${c("subjectId")}::text, ${m("id")}::text, null::text,
      ${m("sentAt")}
    from ${messaging.table("messages")} m
    join ${messaging.table("conversations")} c on ${c("id")} = ${m("conversation")} and ${c("kind")} = 'subject'
    where v_me = any (${m("mentions")})
      and ${m("deletedAt")} is null
      and ${m("sentAt")} > now() - interval '30 days'
      and ${myWorkTenant(m("tenant"))}`,
      },
    ];
  },
};

export const COMMENTS: BlockSqlDefinition = {
  contributes: CONTRIBUTES,
  internal: ["comment_message_readable", "comments_json", "comment_sent"],
  name: "comments",
  scopes: ["tenant"],
  title: "Comments",
  description:
    "Comments on any record as its conversation on the messaging core: whoever reads the record reads them, with replies, mentions and mention groups, anchors, files, edits with history, pins, resolved threads and read markers. The author and the mentioned follow the record and its followers hear of new comments (with notifications), and a comment becomes a work item (with tasks).",
  requires: ["memberships", "permissions", "subjects", "messaging"],
  integrates: ["notifications", "tasks", "reactions", "attachments"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 9,
  upgrades: [
    {
      from: 1,
      description:
        "list_comments takes skip for offset paging; comment_counts counts comments per subject.",
      sql: (ctx) =>
        `drop function if exists ${ctx.fn("list_comments")}(${ctx.idType}, text, text, timestamptz, integer);`,
    },
    {
      from: 2,
      description:
        "Without notifications or the outbox, comments have no after-write trigger.",
      sql: () => "",
    },
    {
      from: 3,
      description:
        "list_activity tags each entry with its source, checks can_subject for registered subjects and returns the subject's audit entries; comment authors and mentioned members follow the subject.",
      sql: () => "",
    },
    {
      from: 4,
      description:
        "list_comments takes after_id, so a cursor page doesn't skip comments created in the same instant.",
      sql: (ctx) =>
        `drop function if exists ${ctx.fn("list_comments")}(${ctx.idType}, text, text, timestamptz, integer, integer);`,
    },
    {
      from: 5,
      description:
        "list_activity takes sources and returns a registered subject's notification deliveries and workflow runs.",
      sql: (ctx) =>
        `drop function if exists ${ctx.fn("list_activity")}(${ctx.idType}, text, text, timestamptz, integer);`,
    },
    {
      from: 6,
      description:
        "With profiles, list_comments returns each comment's author with a name and avatar.",
      sql: () => "",
    },
    TO_MESSAGING,
    {
      from: 8,
      description:
        "list_comments takes include_deleted; false leaves deleted comments out instead of returning placeholders.",
      sql: (ctx) =>
        `drop function if exists ${ctx.fn("list_comments")}(${ctx.idType}, text, text, timestamptz, integer, integer, uuid);`,
    },
  ],
  deprecated: [
    {
      kind: "table",
      symbol: "better_supabase.comments",
      use: "better_supabase.messages (a record's conversation, kind subject)",
      since: "0.14.0",
      removed: "0.14.0",
    },
    {
      kind: "function",
      symbol: "better_supabase.edit_comment",
      use: "better_supabase.edit_message(message, body, attrs)",
      since: "0.14.0",
      removed: "0.14.0",
    },
    {
      kind: "function",
      symbol: "better_supabase.delete_comment",
      use: "better_supabase.delete_message(message)",
      since: "0.14.0",
      removed: "0.14.0",
    },
    {
      kind: "function",
      symbol: "better_supabase.comment_subject_readable",
      use: "better_supabase.can_subject(subject_type, subject_id, 'read')",
      since: "0.14.0",
      removed: "0.14.0",
    },
  ],
  names: NAMES,
  contract,
  build,
};
