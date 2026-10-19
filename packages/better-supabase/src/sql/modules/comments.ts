import type { CommentsEvents } from "../../blocks/comments/events.ts";
import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleEvents,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition, ModuleLayout } from "../module-types.ts";

import { isRecord } from "../../core/guards.ts";
import { sqlIdent, sqlString } from "../../core/template.ts";
import { NOTHING } from "../context.ts";
import {
  addExtraColumns,
  extraFieldsArg,
  jsonSchemaChecks,
  quotedTable,
  SERVICE_CALLER,
  schemaPreamble,
  pageSize,
  revokeTable,
  fail,
  withExtraFields,
} from "../shared.ts";
import {
  qualifiedTable,
  type Subject,
  subjectAccess,
  subjectCascades,
  subjectIdMatches,
  subjectReadable,
  subjectsOption,
} from "../subjects.ts";
import { moduleOperations } from "./access-model.ts";
import { type ActivitySourceName, activityReads } from "./comments-activity.ts";
import { commentWrites } from "./comments-writes.ts";

const EVENTS: ModuleEvents<CommentsEvents> = {
  "comment.deleted": {
    subject: "comments",
    payload: [
      "commentId",
      "organizationId",
      "subjectType",
      "subjectId",
      "authorId",
    ],
  },
  "comment.created": {
    subject: "comments",
    payload: [
      "commentId",
      "organizationId",
      "subjectType",
      "subjectId",
      "authorId",
      "parentId",
      "mentionIds",
    ],
  },
  "comment.mentioned": {
    subject: "comments",
    payload: [
      "commentId",
      "organizationId",
      "subjectType",
      "subjectId",
      "authorId",
      "mentionIds",
    ],
  },
};

const NAMES: ModuleNames = {
  events: EVENTS,
  options: [
    "subjects",
    "maxBodyLength",
    "documentSchema",
    "notify",
    "follow",
    "mentionGroups",
    "extraColumns",
  ],
  tables: {
    comments: {
      name: "comments",
      lifecycle: { user: "author", tenant: "tenant" },
      columns: {
        id: "id",
        tenant: "organization_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        author: "author_id",
        body: "body",
        document: "document",
        mentions: "mentions",
        parent: "parent_id",
        createdAt: "created_at",
        editedAt: "edited_at",
        deletedAt: "deleted_at",
      },
    },
    activity: {
      name: "activity_entries",
      lifecycle: { tenant: "tenant" },
      columns: {
        id: "id",
        tenant: "organization_id",
        event: "event_id",
        type: "type",
        actor: "actor_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        summary: "summary",
        data: "data",
        occurredAt: "occurred_at",
      },
    },
  },
};

/** The keys a comment read returns next to the extra columns. */
const RESERVED = ["fields"] as const;

/** Sorts after every uuid, so `after` without `after_id` means strictly later. */
const MAX_UUID = "'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid";

/** One commentable subject type: its table, and who may read it. */
export type CommentSubject = Omit<Subject, "extra">;

/** `options.documentSchema`: a JSON Schema object for the `document` column. */
function documentSchemaOf(
  ctx: ModuleContext,
): Readonly<Record<string, unknown>> | undefined {
  const option = ctx.option("documentSchema");

  if (option === undefined) {
    return undefined;
  }

  if (!isRecord(option)) {
    throw new TypeError(
      "blocks.comments.options.documentSchema must be a JSON Schema object",
    );
  }

  if (!ctx.installed("jsonb-schemas")) {
    throw new TypeError(
      "blocks.comments.options.documentSchema: add the jsonb-schemas module, which installs pg_jsonschema for the check",
    );
  }

  return option;
}

interface MentionGroups {
  readonly table: string;
  readonly group: string;
  readonly member: string;
  readonly tenant?: string;
}

const MENTION_GROUP_KEYS = new Set(["table", "group", "member", "tenant"]);

function mentionGroupsOf(ctx: ModuleContext): MentionGroups | undefined {
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

/**
 * With notifications (and its subscriptions table) and `options.follow`
 * (default true): the comments_after_write statement that makes the author
 * of a new comment and its newly mentioned members follow the subject.
 */
function followSql(ctx: ModuleContext, c: (logical: string) => string): string {
  if (!ctx.installed("notifications") || !ctx.flag("follow", true)) {
    return "";
  }

  const n = ctx.of("notifications");

  if (!n.hasTable("subscriptions")) {
    return "";
  }

  const s = (logical: string): string => n.col("subscriptions", logical);
  const tenant = n.has("subscriptions", "tenant");

  const columns = [
    ...(tenant ? [s("tenant")] : []),
    s("user"),
    s("subjectType"),
    s("subjectId"),
    s("level"),
  ];

  const values = [
    ...(tenant ? [`new.${c("tenant")}`] : []),
    "f.x",
    `new.${c("subjectType")}`,
    `new.${c("subjectId")}`,
    "'participating'",
  ];

  return `
  -- The author and newly mentioned members follow the subject
  -- (participating); a level a member already chose stays.
  insert into ${n.table("subscriptions")} (${columns.join(", ")})
  select distinct ${values.join(", ")}
  from unnest(case when tg_op = 'INSERT' then array[new.${c("author")}] else '{}'::uuid[] end || v_new) f(x)
  where f.x is not null
  on conflict do nothing;`;
}

function build(ctx: ModuleContext, layout: ModuleLayout): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const id = ctx.idType;
  const comments = ctx.table("comments");
  const activity = ctx.table("activity");
  const c = (logical: string): string => ctx.col("comments", logical);
  const a = (logical: string): string => ctx.col("activity", logical);
  const fn = (name: string): string => ctx.fn(name);
  const extras = ctx.extraColumns("comments", RESERVED);
  const extra = extraFieldsArg(extras);
  const extraIdents = extras.map((column) => column.ident);

  // A comment row as JSON, with the extra columns under fields.
  const commentJson = (row: string, json: string): string =>
    withExtraFields(json, row, extras);

  const reads = activityReads(ctx);
  const permissions = moduleOperations("comments");

  const permission = (action: keyof typeof permissions): string =>
    ctx.permission(action, permissions[action]);

  const maxBody = ctx.number("maxBodyLength", 10_000);

  if (!Number.isInteger(maxBody) || maxBody < 1) {
    throw new TypeError(
      "blocks.comments.options.maxBodyLength must be a whole number above zero",
    );
  }

  const subjects = subjectsOption(ctx, [
    "permissions",
    "label",
    "path",
    "readableBy",
    "scope",
  ]);

  const access = subjectAccess(ctx, {
    subjects,
    actions: ["read", "create", "moderate"],
    permission,
    provider: layout.accessProvider,
  });

  const readable = subjectReadable(ctx, subjects, {
    type: "subject_type",
    id: "subject_id",
    tenant: "tenant",
  });

  // Without options.subjects every subject is readable, so the policies
  // leave out the per-row call that would only return true.
  const subjectCheck =
    subjects.length === 0
      ? ""
      : ` and ${fn("comment_subject_readable")}(${c("subjectType")}, ${c("subjectId")}, ${c("tenant")})`;

  const documentSchema = documentSchemaOf(ctx);
  const target = ctx.tableName("comments");

  const documentCheck = documentSchema
    ? jsonSchemaChecks([
        {
          table: `${target.schema}.${target.name}`,
          column: c("document").replaceAll('"', ""),
          schema: documentSchema,
        },
      ])
    : "";

  const cascades = subjectCascades(
    ctx,
    subjects,
    `delete from ${comments} x where x.${c("subjectType")} = v_type and x.${c("subjectId")} = v_id;`,
  );

  // options.subjects.<type>.label, path and readableBy: SQL on the subject
  // row {row} (and the mentioned user {user} for readableBy).
  // readableBy also takes { sql, enforce }: enforce applies it to the read
  // policy too, so a member sees only the comments on rows it lets them read.
  const expression = (
    type: string,
    subject: Subject,
    key: string,
  ): string | undefined => {
    const where = `blocks.comments.options.subjects.${type}.${key}`;
    const raw = subject.extra[key];

    if (raw !== undefined && key === "readableBy" && isRecord(raw)) {
      for (const name of Object.keys(raw)) {
        if (name !== "sql" && name !== "enforce") {
          throw new TypeError(
            `${where}.${name} is not an option. Options: sql, enforce`,
          );
        }
      }

      if (raw["enforce"] !== undefined && typeof raw["enforce"] !== "boolean") {
        throw new TypeError(`${where}.enforce must be true or false`);
      }
    }

    const object = key === "readableBy" && isRecord(raw);
    const value = object ? raw["sql"] : raw;

    if (value === undefined && !object) {
      return undefined;
    }

    if (typeof value !== "string" || !value.includes("{row}")) {
      throw new TypeError(`${where} must be SQL on the subject row {row}`);
    }

    return value.replaceAll("{row}", "s");
  };

  const enforcedCases = subjects.flatMap(([type, subject]) => {
    const raw = subject.extra["readableBy"];
    const sql = expression(type, subject, "readableBy");

    return sql === undefined || !isRecord(raw) || raw["enforce"] !== true
      ? []
      : [
          `when ${sqlString(type)} then exists (select 1 from ${qualifiedTable(subject.table)} s where ${subjectIdMatches(subject, `${comments}.${c("subjectId")}::text`)} and (${sql.replaceAll("{user}", "(select auth.uid())")}))`,
        ];
  });

  const readableByCheck =
    enforcedCases.length === 0
      ? ""
      : `\n    and case ${c("subjectType")} ${enforcedCases.join(" ")} else true end`;

  for (const [type, subject] of subjects) {
    for (const key of ["label", "path", "readableBy"]) {
      expression(type, subject, key);
    }
  }

  const subjectValue = (key: "label" | "path"): string => {
    const cases = subjects.flatMap(([type, subject]) => {
      const value = expression(type, subject, key);

      return value === undefined
        ? []
        : [
            `when ${sqlString(type)} then (select (${value})::text from ${qualifiedTable(subject.table)} s where ${subjectIdMatches(subject, `new.${c("subjectId")}::text`)} limit 1)`,
          ];
    });

    return cases.length === 0
      ? "null::text"
      : `case new.${c("subjectType")} ${cases.join(" ")} end`;
  };

  // A mentioned member must be able to read comments on the subject: the
  // subject's read key, its permission and readableBy when it sets them.
  const mentionable = (user: string): string => {
    const key = access.keyFor(`new.${c("subjectType")}`, "read");

    const subjectCases = subjects.flatMap(([type, subject]) => {
      const checks: string[] = [];

      if (subject.permission !== undefined) {
        checks.push(
          ctx.scope.canUser(
            user,
            `new.${c("tenant")}`,
            sqlString(subject.permission),
          ),
        );
      }

      const readableBy = expression(type, subject, "readableBy");

      if (readableBy !== undefined) {
        checks.push(
          `exists (select 1 from ${qualifiedTable(subject.table)} s where ${subjectIdMatches(subject, `new.${c("subjectId")}::text`)} and (${readableBy.replaceAll("{user}", user)}))`,
        );
      }

      return checks.length === 0
        ? []
        : [`when ${sqlString(type)} then ${checks.join(" and ")}`];
    });

    return `${ctx.scope.canUser(user, `new.${c("tenant")}`, key)}${
      subjectCases.length === 0
        ? ""
        : `
      and case new.${c("subjectType")} ${subjectCases.join(" ")} else true end`
    }`;
  };

  const groups = mentionGroupsOf(ctx);

  const expand = (mentions: string): string =>
    groups === undefined
      ? `unnest(${mentions})`
      : `(select m.x from unnest(${mentions}) m(x) union select g.${sqlIdent(groups.member)} from ${quotedTable(groups.table)} g where g.${sqlIdent(groups.group)} = any(${mentions})${groups.tenant === undefined ? "" : ` and g.${sqlIdent(groups.tenant)} = new.${c("tenant")}`})`;

  const newMentions =
    groups === undefined
      ? `select x from unnest(new.${c("mentions")}) x
    where (tg_op = 'INSERT' or not x = any(old.${c("mentions")}))
      and ${mentionable("x")}`
      : `select e.x from ${expand(`new.${c("mentions")}`)} e(x)
    where e.x is distinct from new.${c("author")}
      and (tg_op = 'INSERT' or not e.x = any(array(select o.x from ${expand(`old.${c("mentions")}`)} o(x))))
      and ${mentionable("e.x")}`;

  const notify = ctx.flag("notify", true);

  const notifications =
    ctx.installed("notifications") && notify
      ? `
  -- notify() trusts only the service role, so the mention is sent as it,
  -- with the comment's author as the actor; the claims are restored after.
  if cardinality(v_new) > 0 then
    ${ctx.notify(
      `jsonb_build_object(
      'type', 'comment.mentioned',
      'tenant', new.${c("tenant")},
      'actor', new.${c("author")},
      'subject_type', new.${c("subjectType")},
      'subject_id', new.${c("subjectId")},
      'summary', left(new.${c("body")}, 140),
      'subject_label', ${subjectValue("label")},
      'action_path', ${subjectValue("path")},
      'recipients', to_jsonb(v_new),
      'key', 'comment.mentioned:' || new.${c("id")}::text || ':' || md5(array_to_string(v_new, ',')),
      'data', jsonb_build_object('commentId', new.${c("id")})
    )`,
      { indent: "    " },
    )}
  end if;`
      : "";

  const followers = followSql(ctx, c);

  const payload = (extra: string): string =>
    `jsonb_build_object('commentId', new.${c("id")}, 'organizationId', new.${c("tenant")}::text, 'subjectType', new.${c("subjectType")}, 'subjectId', new.${c("subjectId")}, 'authorId', new.${c("author")}${extra})`;

  const subject = `'comments/' || new.${c("id")}::text`;
  const tenant = `new.${c("tenant")}`;

  const created = ctx.record({
    type: "comment.created",
    payload: payload(
      `, 'parentId', new.${c("parent")}, 'mentionIds', to_jsonb(new.${c("mentions")})`,
    ),
    subject,
    tenant,
    audit: false,
  });

  const mentioned = ctx.record({
    type: "comment.mentioned",
    payload: payload(`, 'mentionIds', to_jsonb(v_new)`),
    subject,
    tenant,
    audit: false,
  });

  const deleted = ctx.record({
    type: "comment.deleted",
    payload: payload(""),
    subject,
    tenant,
    audit: {
      category: "data",
      targetType: "comment",
      recordId: `new.${c("id")}::text`,
    },
  });

  return `${schemaPreamble(ctx)}
-- Comments on any subject in a tenant. options.subjects maps each subject
-- type to its table, so the policies require that the caller can read the
-- subject; without it any subject type is accepted.
create table if not exists ${comments} (
  ${c("id")} uuid primary key default gen_random_uuid(),
  ${c("tenant")} ${ctx.scope.column()},
  ${c("subjectType")} text not null check (${c("subjectType")} ~ '^[a-z][a-z0-9_]{0,62}$'),
  ${c("subjectId")} text not null check (length(${c("subjectId")}) between 1 and 200),
  ${c("author")} uuid references auth.users (id) on delete set null default auth.uid(),
  ${c("body")} text not null check (length(${c("body")}) <= ${String(maxBody)}),
  ${c("document")} jsonb,
  ${c("mentions")} uuid[] not null default '{}',
  ${c("parent")} uuid references ${comments} (${c("id")}) on delete cascade,
  -- clock_timestamp keeps a thread in order within one transaction.
  ${c("createdAt")} timestamptz not null default clock_timestamp(),
  ${c("editedAt")} timestamptz,
  ${c("deletedAt")} timestamptz,
  check (${c("deletedAt")} is not null or length(btrim(${c("body")})) > 0)
);
alter table ${comments} add column if not exists ${c("document")} jsonb;${addExtraColumns(comments, extras)}
create index if not exists comments_subject_idx on ${comments} (${c("tenant")}, ${c("subjectType")}, ${c("subjectId")}, ${c("createdAt")});
create index if not exists comments_author_idx on ${comments} (${c("author")});
create index if not exists comments_parent_idx on ${comments} (${c("parent")});
alter table ${comments} enable row level security;
${revokeTable(comments)}
grant select on ${comments} to authenticated;
grant insert (${[c("tenant"), c("subjectType"), c("subjectId"), c("body"), c("document"), c("mentions"), c("parent"), ...extraIdents].join(", ")}) on ${comments} to authenticated;
grant update (${[c("body"), c("document"), c("mentions"), c("deletedAt"), ...extraIdents].join(", ")}) on ${comments} to authenticated;
grant all on ${comments} to service_role;

-- Whether the caller may read a subject: its row is visible to them (the
-- subject table's own policies apply) and they hold its permission.
create or replace function ${fn("comment_subject_readable")}(subject_type text, subject_id text, tenant ${id})
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select ${readable}
$$;

drop policy if exists "comments_read" on ${comments};
create policy "comments_read" on ${comments} for select to authenticated
  using (${access.memberOn(c("tenant"), c("subjectType"), c("subjectId"), "read")}${subjectCheck}${readableByCheck});
drop policy if exists "comments_insert" on ${comments};
create policy "comments_insert" on ${comments} for insert to authenticated
  with check (
    ${c("author")} = (select auth.uid())
    and ${access.canOn(c("tenant"), c("subjectType"), c("subjectId"), "create")}${subjectCheck}
  );
drop policy if exists "comments_update" on ${comments};
create policy "comments_update" on ${comments} for update to authenticated
  using (${c("author")} = (select auth.uid()) or ${access.memberOn(c("tenant"), c("subjectType"), c("subjectId"), "moderate")})
  with check (${c("author")} = (select auth.uid()) or ${access.memberOn(c("tenant"), c("subjectType"), c("subjectId"), "moderate")});

-- Keeps mentions to distinct members other than the author, a reply on its
-- parent's subject, and edited_at; a deleted comment keeps no body.
create or replace function ${fn("comments_before_write")}()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and old.${c("deletedAt")} is not null then
    ${fail("COMMENT_DELETED", "This comment was deleted", "P0001")}
  end if;
  if new.${c("deletedAt")} is not null then
    new.${c("body")} := '';
    new.${c("document")} := null;
    new.${c("mentions")} := '{}';
    return new;
  end if;
  new.${c("mentions")} := array(
    select distinct x from unnest(new.${c("mentions")}) x
    where x is not null and x is distinct from new.${c("author")}
    order by x
  );
  if tg_op = 'INSERT' and new.${c("parent")} is not null and not exists (
    select 1 from ${comments} p
    where p.${c("id")} = new.${c("parent")} and ${ctx.scope.eq(`p.${c("tenant")}`, `new.${c("tenant")}`)}
      and p.${c("subjectType")} = new.${c("subjectType")} and p.${c("subjectId")} = new.${c("subjectId")}
  ) then
    ${fail("COMMENT_PARENT_MISMATCH", "A reply must be on its parent's subject", "23514")}
  end if;
  if tg_op = 'UPDATE' and (new.${c("body")} is distinct from old.${c("body")} or new.${c("document")} is distinct from old.${c("document")} or new.${c("mentions")} is distinct from old.${c("mentions")}) then
    if old.${c("author")} is distinct from auth.uid() and not (${SERVICE_CALLER}) then
      ${fail("COMMENT_NOT_AUTHOR", "Only the author edits a comment")}
    end if;
    new.${c("editedAt")} := now();
  end if;
  return new;
end;
$$;
drop trigger if exists ${ctx.trigger("comments_before_write")} on ${comments};
create trigger ${ctx.trigger("comments_before_write")}
  before insert or update on ${comments}
  for each row execute function ${fn("comments_before_write")}();

${
  [created, mentioned, deleted].some((sql) => sql !== NOTHING) ||
  notifications ||
  followers
    ? `-- Notifies newly mentioned members who can read comments in the tenant,
-- makes the author and them follow the subject, and writes comment.created,
-- comment.mentioned and comment.deleted to the outbox when it is installed.
create or replace function ${fn("comments_after_write")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_new uuid[];
  v_claims text;
begin
  if tg_op = 'UPDATE' and new.${c("deletedAt")} is not null then
    ${deleted}
    return null;
  end if;
  v_new := array(
    ${newMentions}
  );
  if tg_op = 'INSERT' then
    ${created}
  end if;
  if cardinality(v_new) > 0 then
    ${mentioned}
  end if;${notifications}${followers}
  return null;
end;
$$;
revoke execute on function ${fn("comments_after_write")}() from public, anon, authenticated;
drop trigger if exists ${ctx.trigger("comments_after_write")} on ${comments};
create trigger ${ctx.trigger("comments_after_write")}
  after insert or update of ${c("mentions")}, ${c("deletedAt")} on ${comments}
  for each row execute function ${fn("comments_after_write")}();`
    : `-- Without notifications or the outbox there is nothing to send after a write.
drop trigger if exists ${ctx.trigger("comments_after_write")} on ${comments};
drop function if exists ${fn("comments_after_write")}();`
}

${commentWrites(ctx, extras)}

-- Copies a subject's thread to another subject in the same tenant (a quote
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
  copied integer;
begin
  if not (${SERVICE_CALLER}) then
    ${fail("COMMENT_FORBIDDEN", "Only the service role copies comments")}
  end if;
  with copies as materialized (
    select y.${c("id")} as old_id, gen_random_uuid() as new_id
    from ${comments} y
    where ${ctx.scope.eq(`y.${c("tenant")}`, ctx.scope.value("copy_comments.tenant"))}
      and y.${c("subjectType")} = copy_comments.from_type
      and y.${c("subjectId")} = copy_comments.from_id
  ), inserted as (
    insert into ${comments} (${[c("id"), c("tenant"), c("subjectType"), c("subjectId"), c("author"), c("body"), c("document"), c("mentions"), c("parent"), c("createdAt"), c("editedAt"), c("deletedAt"), ...extraIdents].join(", ")})
    select m.new_id, y.${c("tenant")}, copy_comments.to_type, copy_comments.to_id, y.${c("author")},
      y.${c("body")}, y.${c("document")}, '{}', p.new_id, y.${c("createdAt")}, y.${c("editedAt")}, y.${c("deletedAt")}${extraIdents.map((ident) => `, y.${ident}`).join("")}
    from ${comments} y
    join copies m on m.old_id = y.${c("id")}
    left join copies p on p.old_id = y.${c("parent")}
    order by y.${c("createdAt")}, y.${c("id")}
    returning 1
  )
  select count(*)::integer into copied from inserted;
  return copied;
end;
$$;

create or replace function ${fn("delete_comment")}(id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$
  with removed as (
    update ${comments} x set ${c("deletedAt")} = now()
    where x.${c("id")} = delete_comment.id and x.${c("deletedAt")} is null
    returning 1
  )
  select exists (select 1 from removed)
$$;

-- A subject's thread, oldest first; deleted comments stay as placeholders
-- so replies keep their parent. Page with after and after_id (the last
-- comment's created_at and id, so comments created in the same instant
-- aren't skipped) or skip (an offset). after alone means strictly later.
drop function if exists ${fn("list_comments")}(${id}, text, text, timestamptz, integer);
drop function if exists ${fn("list_comments")}(${id}, text, text, timestamptz, integer, integer);
create or replace function ${fn("list_comments")}(
  tenant ${id},
  subject_type text,
  subject_id text,
  after timestamptz default null,
  max_rows integer default 100,
  skip integer default 0,
  after_id uuid default null
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${commentJson("x", "to_jsonb(x.*)")} order by x.${c("createdAt")}, x.${c("id")}), '[]'::jsonb)
  from (
    select * from ${comments} y
    where ${ctx.scope.eq(`y.${c("tenant")}`, ctx.scope.value("list_comments.tenant"))}
      and y.${c("subjectType")} = list_comments.subject_type
      and y.${c("subjectId")} = list_comments.subject_id
      and (list_comments.after is null
        or (y.${c("createdAt")}, y.${c("id")}) > (list_comments.after, coalesce(list_comments.after_id, ${MAX_UUID})))
    order by y.${c("createdAt")}, y.${c("id")}
    limit ${pageSize("list_comments.max_rows", 100, 500)}
    offset greatest(coalesce(list_comments.skip, 0), 0)
  ) x
$$;

-- Comments per subject the caller can read, for counters in a list:
-- { subject_id: count }, deleted comments left out. Runs as the caller.
create or replace function ${fn("comment_counts")}(tenant ${id}, subject_type text, subject_ids text[])
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(x.subject_id, x.n), '{}'::jsonb)
  from (
    select y.${c("subjectId")} as subject_id, count(*) as n
    from ${comments} y
    where ${ctx.scope.eq(`y.${c("tenant")}`, ctx.scope.value("comment_counts.tenant"))}
      and y.${c("subjectType")} = comment_counts.subject_type
      and y.${c("subjectId")} = any (comment_counts.subject_ids)
      and y.${c("deletedAt")} is null
    group by 1
  ) x
$$;

-- The activity feed: one row per outbox event, written by activitySink().
create table if not exists ${activity} (
  ${a("id")} uuid primary key default gen_random_uuid(),
  ${a("tenant")} ${ctx.scope.column()},
  ${a("event")} text not null unique,
  ${a("type")} text not null,
  ${a("actor")} uuid references auth.users (id) on delete set null,
  ${a("subjectType")} text,
  ${a("subjectId")} text,
  ${a("summary")} text,
  ${a("data")} jsonb not null default '{}'::jsonb,
  ${a("occurredAt")} timestamptz not null default now()
);
create index if not exists activity_entries_feed_idx on ${activity} (${a("tenant")}, ${a("occurredAt")} desc, ${a("id")} desc);
create index if not exists activity_entries_subject_idx on ${activity} (${a("tenant")}, ${a("subjectType")}, ${a("subjectId")});
create index if not exists activity_entries_actor_idx on ${activity} (${a("actor")});
alter table ${activity} enable row level security;
${revokeTable(activity)}
grant select on ${activity} to authenticated;
grant all on ${activity} to service_role;
${reads.readable}drop policy if exists "activity_entries_read" on ${activity};
create policy "activity_entries_read" on ${activity} for select to authenticated
  using (${ctx.scope.check(a("tenant"), permission("activity"))}${reads.rowCheck});${reads.dropReadable}${reads.helpers}

-- Inserts batch.entries ({ event_id, organization_id, type, actor_id?,
-- subject_type?, subject_id?, summary?, data?, occurred_at? }); a seen
-- event_id is skipped, so a replayed batch writes nothing twice. The list
-- sits in an object so it reaches jsonb the same way over Postgres and the
-- Data API.
create or replace function ${fn("record_activity")}(batch jsonb)
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
declare
  inserted integer;
begin
  if not (${SERVICE_CALLER}) then
    ${fail("ACTIVITY_FORBIDDEN", "Only the service role records activity")}
  end if;
  insert into ${activity} (${[a("event"), a("tenant"), a("type"), a("actor"), a("subjectType"), a("subjectId"), a("summary"), a("data"), a("occurredAt")].join(", ")})
  select e ->> 'event_id', (e ->> 'organization_id')::${id}, e ->> 'type', nullif(e ->> 'actor_id', '')::uuid,
    e ->> 'subject_type', e ->> 'subject_id', e ->> 'summary', coalesce(e -> 'data', '{}'::jsonb),
    coalesce((e ->> 'occurred_at')::timestamptz, now())
  from jsonb_array_elements(coalesce(batch -> 'entries', '[]'::jsonb)) e
  on conflict (${a("event")}) do nothing;
  get diagnostics inserted = row_count;
  return inserted;
end;
$$;

drop function if exists ${fn("list_activity")}(${id}, text, text, timestamptz, integer);

-- A tenant's activity, newest first, or one subject's timeline with
-- subject_type and subject_id; before pages back, and sources (null for
-- all) picks the kinds of entry. Runs as the caller, and each entry carries
-- source: ${sourcesComment(reads.sources)}.${reads.gate === "" ? "" : "\n-- A registered subject's timeline is empty unless can_subject grants read."}
create or replace function ${fn("list_activity")}(
  tenant ${id},
  subject_type text default null,
  subject_id text default null,
  before timestamptz default null,
  max_rows integer default 50,
  sources text[] default null
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_limit integer := ${pageSize("list_activity.max_rows", 50, 500)};
  v_rows jsonb;${reads.auditBranch === "" ? "" : "\n  v_table text;"}
begin${reads.gate}${reads.auditSetup}
  select coalesce(jsonb_agg(x.entry order by x.at desc, x.id desc), '[]'::jsonb)
  into v_rows
  from (
    select u.entry, u.at, u.id from (
    (select to_jsonb(y.*) || jsonb_build_object('source', 'event') as entry,
      y.${a("occurredAt")} as at, y.${a("id")}::text as id
    from ${activity} y
    where ${ctx.scope.eq(`y.${a("tenant")}`, ctx.scope.value("list_activity.tenant"))}
      and (list_activity.sources is null or 'event' = any (list_activity.sources))
      and (list_activity.subject_type is null or y.${a("subjectType")} = list_activity.subject_type)
      and (list_activity.subject_id is null or y.${a("subjectId")} = list_activity.subject_id)
      and (list_activity.before is null or y.${a("occurredAt")} < list_activity.before)
    order by y.${a("occurredAt")} desc, y.${a("id")} desc
    limit v_limit)${reads.auditBranch}${reads.sourceBranches}
    ) u
    order by u.at desc, u.id desc
    limit v_limit
  ) x;
  return v_rows;
end;
$$;
${cascades}${documentCheck}
revoke execute on function ${fn("comment_subject_readable")}(text, text, ${id}) from public, anon;
revoke execute on function ${fn("create_comment")}(${id}, text, text, text, uuid[], uuid, jsonb${extra.type}) from public, anon;
revoke execute on function ${fn("edit_comment")}(uuid, text, uuid[], jsonb, boolean${extra.type}) from public, anon;
revoke execute on function ${fn("copy_comments")}(${id}, text, text, text, text) from public, anon, authenticated;
revoke execute on function ${fn("list_activity")}(${id}, text, text, timestamptz, integer, text[]) from public, anon;
revoke execute on function ${fn("delete_comment")}(uuid) from public, anon;
revoke execute on function ${fn("list_comments")}(${id}, text, text, timestamptz, integer, integer, uuid) from public, anon;
revoke execute on function ${fn("comment_counts")}(${id}, text, text[]) from public, anon;
revoke execute on function ${fn("record_activity")}(jsonb) from public, anon, authenticated;
grant execute on function ${fn("comment_subject_readable")}(text, text, ${id}) to authenticated, service_role;
grant execute on function ${fn("create_comment")}(${id}, text, text, text, uuid[], uuid, jsonb${extra.type}) to authenticated, service_role;
grant execute on function ${fn("edit_comment")}(uuid, text, uuid[], jsonb, boolean${extra.type}) to authenticated, service_role;
grant execute on function ${fn("copy_comments")}(${id}, text, text, text, text) to service_role;
grant execute on function ${fn("list_activity")}(${id}, text, text, timestamptz, integer, text[]) to authenticated, service_role;
grant execute on function ${fn("delete_comment")}(uuid) to authenticated, service_role;
grant execute on function ${fn("list_comments")}(${id}, text, text, timestamptz, integer, integer, uuid) to authenticated, service_role;
grant execute on function ${fn("comment_counts")}(${id}, text, text[]) to authenticated, service_role;
grant execute on function ${fn("record_activity")}(jsonb) to service_role;`;
}

const SOURCE_COMMENTS: Readonly<Record<ActivitySourceName, string>> = {
  event: "event for an activity entry",
  audit: "audit for an audit log entry on the subject's row",
  delivery: "delivery for a notification delivery about the subject",
  run: "run for a workflow run on the subject",
};

function sourcesComment(sources: readonly ActivitySourceName[]): string {
  return sources.map((source) => SOURCE_COMMENTS[source]).join(",\n-- ");
}

function contract(ctx: ModuleContext): readonly ModuleContractFunction[] {
  const extra = extraFieldsArg(ctx.extraColumns("comments", RESERVED)).contract;

  return [
    {
      name: "comment_subject_readable",
      args: ["text", "text", "{id}"],
      returns: "boolean",
    },
    {
      name: "create_comment",
      args: [
        "{id}",
        "text",
        "text",
        "text",
        "uuid[]",
        "uuid",
        "jsonb",
        ...extra,
      ],
      returns: "jsonb",
    },
    {
      name: "edit_comment",
      args: ["uuid", "text", "uuid[]", "jsonb", "boolean", ...extra],
      returns: "jsonb",
    },
    {
      name: "copy_comments",
      args: ["{id}", "text", "text", "text", "text"],
      returns: "integer",
    },
    {
      name: "list_activity",
      args: [
        "{id}",
        "text",
        "text",
        "timestamp with time zone",
        "integer",
        "text[]",
      ],
      returns: "jsonb",
    },
    { name: "delete_comment", args: ["uuid"], returns: "boolean" },
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
      ],
      returns: "jsonb",
    },
    {
      name: "comment_counts",
      args: ["{id}", "text", "text[]"],
      returns: "jsonb",
    },
    { name: "record_activity", args: ["jsonb"], returns: "integer" },
  ];
}

export const COMMENTS: ModuleDefinition = {
  internal: [
    "comment_subject_readable",
    "activity_subject_readable",
    "activity_subject_deliveries",
  ],
  // comments_before_write refuses any update to a deleted comment.
  hidingColumns: ["comments.deletedAt"],
  name: "comments",
  scopes: ["tenant", "user", "none"],
  title: "Comments and activity",
  description:
    "Comments on any subject in a tenant, with replies, mentions that notify (with the notifications module) and comment.* outbox events, plus an activity_entries feed that activitySink() fills from outbox events, filtered by can_subject and joined with the subject's audit entries, notification deliveries and workflow runs when subjects, audit, notifications and workflows are installed.",
  requires: ["tenant", "access"],
  integrates: [
    "jsonb-schemas",
    "notifications",
    "subjects",
    "audit",
    "workflows",
  ],
  providerFunctions: ["idsWithFor"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 6,
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
  ],
  names: NAMES,
  contract,
  build,
};
