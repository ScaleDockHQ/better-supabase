import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../registry.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { NOTHING } from "../context.ts";
import {
  jsonSchemaChecks,
  quotedTable,
  SERVICE_CALLER,
  schemaPreamble,
  tenantIn,
  pageSize,
} from "../shared.ts";
import {
  qualifiedTable,
  type Subject,
  subjectCascades,
  subjectIdMatches,
  subjectReadable,
  subjectsOption,
} from "../subjects.ts";
import { MODULE_PERMISSIONS } from "./access-model.ts";

const NAMES: ModuleNames = {
  options: [
    "subjects",
    "maxBodyLength",
    "documentSchema",
    "notify",
    "mentionGroups",
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

/** One commentable subject type: its table, and who may read it. */
export type CommentSubject = Omit<Subject, "extra">;

const isObject = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

/** `options.documentSchema`: a JSON Schema object for the `document` column. */
function documentSchemaOf(
  ctx: ModuleContext,
): Readonly<Record<string, unknown>> | undefined {
  const option = ctx.option("documentSchema");
  if (option === undefined) return undefined;
  if (!isObject(option)) {
    throw new TypeError(
      "sql.modules.comments.options.documentSchema must be a JSON Schema object",
    );
  }
  if (!ctx.installed("jsonb-schemas")) {
    throw new TypeError(
      "sql.modules.comments.options.documentSchema: add the jsonb-schemas module, which installs pg_jsonschema for the check",
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
  if (option === undefined) return undefined;
  const where = "sql.modules.comments.options.mentionGroups";
  if (!isObject(option)) {
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
    if (value === undefined) return undefined;
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

function build(ctx: ModuleContext): string {
  if (ctx.mode === "custom") return "";
  const id = ctx.idType;
  const comments = ctx.table("comments");
  const activity = ctx.table("activity");
  const c = (logical: string): string => ctx.col("comments", logical);
  const a = (logical: string): string => ctx.col("activity", logical);
  const fn = (name: string): string => ctx.fn(name);
  const permissions = MODULE_PERMISSIONS.comments;
  const permission = (action: keyof typeof permissions): string =>
    ctx.permission(action, permissions[action]);
  const can = (tenant: string, action: keyof typeof permissions): string =>
    ctx.can("tenant", tenant, permission(action));
  const maxBody = ctx.number("maxBodyLength", 10_000);
  if (!Number.isInteger(maxBody) || maxBody < 1) {
    throw new TypeError(
      "sql.modules.comments.options.maxBodyLength must be a whole number above zero",
    );
  }
  const subjects = subjectsOption(ctx, [
    "permissions",
    "label",
    "path",
    "readableBy",
  ]);
  type Action = "read" | "create" | "moderate";
  const actions: ReadonlySet<string> = new Set(["read", "create", "moderate"]);
  // options.subjects.<type>.permissions: a key per action for that subject
  // type, in place of the module's read, create and moderate keys.
  const overrides = subjects.map(
    ([type, subject]): readonly [string, ReadonlyMap<string, string>] => {
      const raw = subject.extra["permissions"];
      const keys = new Map<string, string>();
      if (raw === undefined) return [type, keys];
      const where = `sql.modules.comments.options.subjects.${type}.permissions`;
      if (!isObject(raw)) {
        throw new TypeError(`${where} must be { read?, create?, moderate? }`);
      }
      for (const [key, value] of Object.entries(raw)) {
        if (
          !actions.has(key) ||
          typeof value !== "string" ||
          value.length === 0
        ) {
          throw new TypeError(
            `${where}.${key}: use read, create and moderate with a permission key`,
          );
        }
        keys.set(key, value);
      }
      return [type, keys];
    },
  );
  const canOn = (tenant: string, type: string, action: Action): string => {
    const cases = overrides.flatMap(([subjectType, keys]) => {
      const key = keys.get(action);
      return key === undefined
        ? []
        : [`when ${sqlString(subjectType)} then ${sqlString(key)}`];
    });
    return cases.length === 0
      ? can(tenant, action)
      : `coalesce(better_supabase.can('tenant', ${tenant}, case ${type} ${cases.join(" ")} else ${permission(action)} end), false)`;
  };
  // The policy form of canOn: one tenant_ids_with set per permission key,
  // each computed once per statement, instead of a can() call per row.
  const memberOn = (tenant: string, type: string, action: Action): string => {
    const keyed = overrides.flatMap(([subjectType, keys]) => {
      const key = keys.get(action);
      return key === undefined ? [] : [[subjectType, key] as const];
    });
    if (keyed.length === 0) return tenantIn(tenant, permission(action));
    const branches = keyed.map(
      ([subjectType, key]) =>
        `(${type} = ${sqlString(subjectType)} and ${tenantIn(tenant, sqlString(key))})`,
    );
    const listed = keyed.map(([subjectType]) => sqlString(subjectType));
    branches.push(
      `(${type} not in (${listed.join(", ")}) and ${tenantIn(tenant, permission(action))})`,
    );
    return `(${branches.join(" or ")})`;
  };
  const readable = subjectReadable(subjects, {
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
  const expression = (
    type: string,
    subject: Subject,
    key: string,
  ): string | undefined => {
    const value = subject.extra[key];
    if (value === undefined) return undefined;
    if (typeof value !== "string" || !value.includes("{row}")) {
      throw new TypeError(
        `sql.modules.comments.options.subjects.${type}.${key} must be SQL on the subject row {row}`,
      );
    }
    return value.replaceAll("{row}", "s");
  };
  for (const [type, subject] of subjects)
    for (const key of ["label", "path", "readableBy"])
      expression(type, subject, key);
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
    const keyCases = overrides.flatMap(([type, keys]) => {
      const key = keys.get("read");
      return key === undefined
        ? []
        : [`when ${sqlString(type)} then ${sqlString(key)}`];
    });
    const key =
      keyCases.length === 0
        ? permission("read")
        : `case new.${c("subjectType")} ${keyCases.join(" ")} else ${permission("read")} end`;
    const subjectCases = subjects.flatMap(([type, subject]) => {
      const checks: string[] = [];
      if (subject.permission !== undefined) {
        checks.push(
          `coalesce(better_supabase.can_user(${user}, 'tenant', new.${c("tenant")}, ${sqlString(subject.permission)}), false)`,
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
    return `coalesce(better_supabase.can_user(${user}, 'tenant', new.${c("tenant")}, ${key}), false)${
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
  ${c("tenant")} ${id} not null,
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
alter table ${comments} add column if not exists ${c("document")} jsonb;
create index if not exists comments_subject_idx on ${comments} (${c("tenant")}, ${c("subjectType")}, ${c("subjectId")}, ${c("createdAt")});
create index if not exists comments_author_idx on ${comments} (${c("author")});
create index if not exists comments_parent_idx on ${comments} (${c("parent")});
alter table ${comments} enable row level security;
revoke all on ${comments} from anon, authenticated;
grant select on ${comments} to authenticated;
grant insert (${[c("tenant"), c("subjectType"), c("subjectId"), c("body"), c("document"), c("mentions"), c("parent")].join(", ")}) on ${comments} to authenticated;
grant update (${[c("body"), c("document"), c("mentions"), c("deletedAt")].join(", ")}) on ${comments} to authenticated;
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
  using (${memberOn(c("tenant"), c("subjectType"), "read")}${subjectCheck});
drop policy if exists "comments_insert" on ${comments};
create policy "comments_insert" on ${comments} for insert to authenticated
  with check (
    ${c("author")} = (select auth.uid())
    and ${canOn(c("tenant"), c("subjectType"), "create")}${subjectCheck}
  );
drop policy if exists "comments_update" on ${comments};
create policy "comments_update" on ${comments} for update to authenticated
  using (${c("author")} = (select auth.uid()) or ${memberOn(c("tenant"), c("subjectType"), "moderate")})
  with check (${c("author")} = (select auth.uid()) or ${memberOn(c("tenant"), c("subjectType"), "moderate")});

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
    raise exception 'This comment was deleted' using errcode = 'P0001', hint = 'COMMENT_DELETED';
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
    where p.${c("id")} = new.${c("parent")} and p.${c("tenant")} = new.${c("tenant")}
      and p.${c("subjectType")} = new.${c("subjectType")} and p.${c("subjectId")} = new.${c("subjectId")}
  ) then
    raise exception 'A reply must be on its parent''s subject' using errcode = '23514', hint = 'COMMENT_PARENT_MISMATCH';
  end if;
  if tg_op = 'UPDATE' and (new.${c("body")} is distinct from old.${c("body")} or new.${c("document")} is distinct from old.${c("document")} or new.${c("mentions")} is distinct from old.${c("mentions")}) then
    if old.${c("author")} is distinct from auth.uid() and not (${SERVICE_CALLER}) then
      raise exception 'Only the author edits a comment' using errcode = '42501', hint = 'COMMENT_NOT_AUTHOR';
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
  [created, mentioned, deleted].some((sql) => sql !== NOTHING) || notifications
    ? `-- Notifies newly mentioned members who can read comments in the tenant,
-- and writes comment.created, comment.mentioned and comment.deleted to the
-- outbox when it is installed.
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
  end if;${notifications}
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

-- The functions run as the caller, so the policies above decide.
drop function if exists ${fn("create_comment")}(${id}, text, text, text, uuid[], uuid);
drop function if exists ${fn("edit_comment")}(uuid, text, uuid[]);
create or replace function ${fn("create_comment")}(
  tenant ${id},
  subject_type text,
  subject_id text,
  body text,
  mentions uuid[] default '{}',
  parent uuid default null,
  document jsonb default null
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  insert into ${comments} as x (${[c("tenant"), c("subjectType"), c("subjectId"), c("body"), c("document"), c("mentions"), c("parent")].join(", ")})
  values (create_comment.tenant, create_comment.subject_type, create_comment.subject_id, create_comment.body, create_comment.document, coalesce(create_comment.mentions, '{}'), create_comment.parent)
  returning to_jsonb(x.*)
$$;

-- An edit keeps the document unless one is passed or clear_document is true.
create or replace function ${fn("edit_comment")}(id uuid, body text, mentions uuid[] default null, document jsonb default null, clear_document boolean default false)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  update ${comments} x
  set ${c("body")} = edit_comment.body,
      ${c("document")} = case
        when coalesce(edit_comment.clear_document, false) then null
        else coalesce(edit_comment.document, x.${c("document")})
      end,
      ${c("mentions")} = coalesce(edit_comment.mentions, x.${c("mentions")})
  where x.${c("id")} = edit_comment.id
  returning to_jsonb(x.*)
$$;

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
    raise exception 'Only the service role copies comments' using errcode = '42501', hint = 'COMMENT_FORBIDDEN';
  end if;
  with copies as materialized (
    select y.${c("id")} as old_id, gen_random_uuid() as new_id
    from ${comments} y
    where y.${c("tenant")} = copy_comments.tenant
      and y.${c("subjectType")} = copy_comments.from_type
      and y.${c("subjectId")} = copy_comments.from_id
  ), inserted as (
    insert into ${comments} (${[c("id"), c("tenant"), c("subjectType"), c("subjectId"), c("author"), c("body"), c("document"), c("mentions"), c("parent"), c("createdAt"), c("editedAt"), c("deletedAt")].join(", ")})
    select m.new_id, y.${c("tenant")}, copy_comments.to_type, copy_comments.to_id, y.${c("author")},
      y.${c("body")}, y.${c("document")}, '{}', p.new_id, y.${c("createdAt")}, y.${c("editedAt")}, y.${c("deletedAt")}
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
-- so replies keep their parent. Page with after (a cursor) or skip (an offset).
drop function if exists ${fn("list_comments")}(${id}, text, text, timestamptz, integer);
create or replace function ${fn("list_comments")}(
  tenant ${id},
  subject_type text,
  subject_id text,
  after timestamptz default null,
  max_rows integer default 100,
  skip integer default 0
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x.*) order by x.${c("createdAt")}, x.${c("id")}), '[]'::jsonb)
  from (
    select * from ${comments} y
    where y.${c("tenant")} = list_comments.tenant
      and y.${c("subjectType")} = list_comments.subject_type
      and y.${c("subjectId")} = list_comments.subject_id
      and (list_comments.after is null or y.${c("createdAt")} > list_comments.after)
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
    where y.${c("tenant")} = comment_counts.tenant
      and y.${c("subjectType")} = comment_counts.subject_type
      and y.${c("subjectId")} = any (comment_counts.subject_ids)
      and y.${c("deletedAt")} is null
    group by 1
  ) x
$$;

-- The activity feed: one row per outbox event, written by activitySink().
create table if not exists ${activity} (
  ${a("id")} uuid primary key default gen_random_uuid(),
  ${a("tenant")} ${id} not null,
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
revoke all on ${activity} from anon, authenticated;
grant select on ${activity} to authenticated;
grant all on ${activity} to service_role;
drop policy if exists "activity_entries_read" on ${activity};
create policy "activity_entries_read" on ${activity} for select to authenticated
  using (${tenantIn(a("tenant"), permission("activity"))});

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
    raise exception 'Only the service role records activity' using errcode = '42501', hint = 'ACTIVITY_FORBIDDEN';
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

-- A tenant's activity, newest first, or one subject's timeline with
-- subject_type and subject_id; before pages back. Runs as the caller.
create or replace function ${fn("list_activity")}(
  tenant ${id},
  subject_type text default null,
  subject_id text default null,
  before timestamptz default null,
  max_rows integer default 50
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x.*) order by x.${a("occurredAt")} desc, x.${a("id")} desc), '[]'::jsonb)
  from (
    select * from ${activity} y
    where y.${a("tenant")} = list_activity.tenant
      and (list_activity.subject_type is null or y.${a("subjectType")} = list_activity.subject_type)
      and (list_activity.subject_id is null or y.${a("subjectId")} = list_activity.subject_id)
      and (list_activity.before is null or y.${a("occurredAt")} < list_activity.before)
    order by y.${a("occurredAt")} desc, y.${a("id")} desc
    limit ${pageSize("list_activity.max_rows", 50, 500)}
  ) x
$$;
${cascades}${documentCheck}
revoke execute on function ${fn("comment_subject_readable")}(text, text, ${id}) from public, anon;
revoke execute on function ${fn("create_comment")}(${id}, text, text, text, uuid[], uuid, jsonb) from public, anon;
revoke execute on function ${fn("edit_comment")}(uuid, text, uuid[], jsonb, boolean) from public, anon;
revoke execute on function ${fn("copy_comments")}(${id}, text, text, text, text) from public, anon, authenticated;
revoke execute on function ${fn("list_activity")}(${id}, text, text, timestamptz, integer) from public, anon;
revoke execute on function ${fn("delete_comment")}(uuid) from public, anon;
revoke execute on function ${fn("list_comments")}(${id}, text, text, timestamptz, integer, integer) from public, anon;
revoke execute on function ${fn("comment_counts")}(${id}, text, text[]) from public, anon;
revoke execute on function ${fn("record_activity")}(jsonb) from public, anon, authenticated;
grant execute on function ${fn("comment_subject_readable")}(text, text, ${id}) to authenticated, service_role;
grant execute on function ${fn("create_comment")}(${id}, text, text, text, uuid[], uuid, jsonb) to authenticated, service_role;
grant execute on function ${fn("edit_comment")}(uuid, text, uuid[], jsonb, boolean) to authenticated, service_role;
grant execute on function ${fn("copy_comments")}(${id}, text, text, text, text) to service_role;
grant execute on function ${fn("list_activity")}(${id}, text, text, timestamptz, integer) to authenticated, service_role;
grant execute on function ${fn("delete_comment")}(uuid) to authenticated, service_role;
grant execute on function ${fn("list_comments")}(${id}, text, text, timestamptz, integer, integer) to authenticated, service_role;
grant execute on function ${fn("comment_counts")}(${id}, text, text[]) to authenticated, service_role;
grant execute on function ${fn("record_activity")}(jsonb) to service_role;`;
}

function contract(): readonly ModuleContractFunction[] {
  return [
    {
      name: "comment_subject_readable",
      args: ["text", "text", "{id}"],
      returns: "boolean",
    },
    {
      name: "create_comment",
      args: ["{id}", "text", "text", "text", "uuid[]", "uuid", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "edit_comment",
      args: ["uuid", "text", "uuid[]", "jsonb", "boolean"],
      returns: "jsonb",
    },
    {
      name: "copy_comments",
      args: ["{id}", "text", "text", "text", "text"],
      returns: "integer",
    },
    {
      name: "list_activity",
      args: ["{id}", "text", "text", "timestamp with time zone", "integer"],
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
  internal: ["comment_subject_readable"],
  name: "comments",
  title: "Comments and activity",
  description:
    "Comments on any subject in a tenant, with replies, mentions that notify (with the notifications module) and comment.* outbox events, plus an activity_entries feed that activitySink() fills from outbox events.",
  requires: ["tenant", "access"],
  integrates: ["jsonb-schemas", "notifications"],
  providerFunctions: ["idsWithFor"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 3,
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
  ],
  names: NAMES,
  contract,
  build,
};
