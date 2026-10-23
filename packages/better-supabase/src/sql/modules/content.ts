import type { ContentEvents } from "../../blocks/content/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockContributes } from "../contributions.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { lockTable, schemaPreamble } from "../shared.ts";
import { contentFunctions } from "./content-functions.ts";
import { contentPublishFunctions } from "./content-publish.ts";
import {
  CONTENT_STATUSES,
  contentSql,
  publishSchedule,
  SLUG,
} from "./content-sql.ts";

const ENTRY_PAYLOAD = [
  "organizationId",
  "id",
  "type",
  "locale",
  "slug",
  "status",
  "translationGroupId",
] as const;

const entry = { subject: "content-entries", payload: ENTRY_PAYLOAD } as const;

const EVENTS: BlockSqlEvents<ContentEvents> = {
  "content_entry.created": entry,
  "content_entry.updated": entry,
  "content_entry.publish_requested": entry,
  "content_entry.scheduled": entry,
  "content_entry.unscheduled": entry,
  "content_entry.published": entry,
  "content_entry.archived": entry,
};

const NAMES: BlockSqlNames = {
  entities: {
    content_entry: {
      table: "entries",
      singular: "content_entry",
      primary: true,
      subject: {
        title: "title",
        permissions: { read: "read", write: "write" },
        search: { title: "title", body: ["summary"] },
      },
    },
  },
  events: EVENTS,
  hooks: ["before_content_entry_publish", "after_content_entry_publish"],
  options: [
    "types",
    "locales",
    "requireApproval",
    "publishPolicy",
    "publishSchedule",
  ],
  tables: {
    entries: {
      name: "content_entries",
      lifecycle: { tenant: "tenant", user: "author", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        type: "type",
        locale: "locale",
        slug: "slug",
        title: "title",
        summary: "summary",
        body: "body",
        status: "status",
        publishAt: "publish_at",
        publishedAt: "published_at",
        author: "author_id",
        translationGroup: "translation_group_id",
        cover: "cover_attachment_id",
        approval: "approval_id",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
  },
};

function tables(ctx: BlockSqlContext): string {
  const q = contentSql(ctx);
  const { e, entries } = q;

  const name = (suffix: string): string =>
    sqlIdent(`${ctx.tableName("entries").name}_${suffix}`);

  const statuses = CONTENT_STATUSES.map((status) => `'${status}'`).join(", ");

  const cover =
    q.attachments === undefined
      ? ""
      : ` references ${q.attachments.table("attachments")} (${q.attachments.col("attachments", "id")}) on delete set null`;

  return `create table if not exists ${entries} (
  ${e("id")} uuid primary key default gen_random_uuid(),
  ${e("tenant")} ${ctx.idType} not null,
  -- One of options.types and options.locales; the functions check both.
  ${e("type")} text not null,
  ${e("locale")} text not null,
  ${e("slug")} text not null check (length(${e("slug")}) <= 200 and ${e("slug")} ~ ${sqlString(SLUG)}),
  ${e("title")} text not null check (length(${e("title")}) between 1 and 300),
  ${e("summary")} text check (${e("summary")} is null or length(${e("summary")}) <= 2000),
  ${e("body")} jsonb not null default '{}'::jsonb check (jsonb_typeof(${e("body")}) in ('object', 'array')),
  ${e("status")} text not null default 'draft' check (${e("status")} in (${statuses})),
  ${e("publishAt")} timestamptz,
  ${e("publishedAt")} timestamptz,
  ${e("author")} uuid references auth.users (id) on delete set null,
  -- Entries in one group translate each other, one per locale.
  ${e("translationGroup")} uuid not null default gen_random_uuid(),
  ${e("cover")} uuid${cover},
  -- The latest publish request, when options.requireApproval is on.
  ${e("approval")} uuid,
  ${e("createdBy")} uuid,
  ${e("createdAt")} timestamptz not null default now(),
  ${e("updatedAt")} timestamptz not null default now(),
  unique (${e("tenant")}, ${e("type")}, ${e("locale")}, ${e("slug")}),
  unique (${e("tenant")}, ${e("translationGroup")}, ${e("locale")}),
  check (${e("status")} <> 'scheduled' or ${e("publishAt")} is not null),
  check (${e("status")} <> 'published' or ${e("publishedAt")} is not null)
);
create index if not exists ${name("published_idx")} on ${entries} (${e("tenant")}, ${e("type")}, ${e("locale")}, ${e("publishedAt")} desc) where ${e("status")} = 'published';
create index if not exists ${name("due_idx")} on ${entries} (${e("publishAt")}) where ${e("status")} = 'scheduled';
create index if not exists ${name("updated_idx")} on ${entries} (${e("tenant")}, ${e("updatedAt")} desc);
create index if not exists ${name("author_idx")} on ${entries} (${e("author")});

${lockTable(entries, { read: true })}
drop policy if exists ${name("read")} on ${entries};
create policy ${name("read")} on ${entries} for select to authenticated
  using (${ctx.scope.check(e("tenant"), q.read)});
`;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  return `${schemaPreamble(ctx)}
-- Content entries per organization: typed, localized pages and posts with a
-- slug, drafted, scheduled and published, readable by anyone once published.
${tables(ctx)}
${contentFunctions(ctx)}
${contentPublishFunctions(ctx)}`;
}

/** Schedules publish_due_content_entries when pg_cron is installed. */
function data(ctx: BlockSqlContext): string {
  const schedule = ctx.mode === "custom" ? undefined : publishSchedule(ctx);

  if (schedule === undefined) {
    return "";
  }

  const due = ctx.fn("publish_due_content_entries");

  return `-- Publishes scheduled content entries when pg_cron is installed.
do $$
begin
  if pg_catalog.to_regnamespace('cron') is not null then
    perform cron.schedule('better-supabase-content-publish', ${sqlString(schedule)}, ${sqlString(`select ${due}()`)});
  else
    raise notice 'pg_cron is not installed: call ${due.replaceAll("'", "")}() on a schedule to publish scheduled content entries';
  end if;
end;
$$;`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    { name: "create_content_entry", args: ["{id}", "jsonb"], returns: "jsonb" },
    { name: "update_content_entry", args: ["uuid", "jsonb"], returns: "jsonb" },
    { name: "archive_content_entry", args: ["uuid"], returns: "jsonb" },
    { name: "get_content_entry", args: ["uuid"], returns: "jsonb" },
    { name: "list_content_entries", args: ["{id}", "jsonb"], returns: "jsonb" },
    { name: "publish_content_entry", args: ["uuid"], returns: "jsonb" },
    {
      name: "schedule_content_entry",
      args: ["uuid", "timestamptz"],
      returns: "jsonb",
    },
    { name: "publish_due_content_entries", args: [], returns: "integer" },
    {
      name: "public_content_entry",
      args: ["{id}", "text", "text", "text"],
      returns: "jsonb",
    },
    {
      name: "public_content_entries",
      args: ["{id}", "text", "text", "integer", "timestamptz"],
      returns: "jsonb",
    },
  ];
}

const CONTRIBUTES: BlockContributes = {
  approvals: (own) => [
    {
      subject: own.naming.rename("content_entry"),
      access: "declared",
      approve: ({ subjectId }) =>
        `perform ${own.fn("content_entry_approved")}((${subjectId})::uuid);`,
      approvable: ({ subjectId }) =>
        `exists (select 1 from ${own.table("entries")} x where x.${own.col("entries", "id")} = (${subjectId})::uuid and x.${own.col("entries", "status")} = 'draft' and x.${own.col("entries", "approval")} is not null)`,
    },
  ],
};

export const CONTENT: BlockSqlDefinition = {
  contributes: CONTRIBUTES,
  name: "content",
  scopes: ["tenant"],
  title: "Content",
  description:
    "Typed, localized content entries per organization, such as pages and posts, with a slug unique per type and locale. Entries are drafted, scheduled and published, optionally through approvals, and anyone can read published entries.",
  requires: ["memberships", "permissions", "subjects"],
  integrates: ["approvals", "versions", "attachments", "outbox", "audit"],
  target: "schema",
  modes: ["managed", "custom"],
  names: NAMES,
  contract,
  build,
  data,
};
