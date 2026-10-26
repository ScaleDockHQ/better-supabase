import type { ModerationEvents } from "../../blocks/moderation/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { lockTable, schemaPreamble } from "../shared.ts";
import { moderationFunctions } from "./moderation-functions.ts";
import { moduleOperations } from "./permissions-model.ts";

const EVENTS: BlockSqlEvents<ModerationEvents> = {
  "moderation_report.created": {
    subject: "moderation-reports",
    payload: [
      "organizationId",
      "id",
      "itemId",
      "subjectType",
      "subjectId",
      "reason",
    ],
  },
  "moderation_item.decided": {
    subject: "moderation-items",
    payload: [
      "organizationId",
      "id",
      "subjectType",
      "subjectId",
      "authorId",
      "action",
      "status",
      "previousStatus",
      "automatic",
    ],
  },
  "moderation_ban.created": {
    subject: "moderation-bans",
    payload: ["organizationId", "id", "userId", "expiresAt"],
  },
  "moderation_ban.lifted": {
    subject: "moderation-bans",
    payload: ["organizationId", "id", "userId", "expiresAt"],
  },
};

const NAMES: BlockSqlNames = {
  entities: {
    moderation_item: {
      table: "items",
      singular: "moderation_item",
      primary: true,
    },
  },
  events: EVENTS,
  options: ["autoHideThreshold", "reasons"],
  tables: {
    items: {
      name: "moderation_items",
      app: {},
      typed: ["status"],
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        author: "author_id",
        status: "status",
        openReports: "open_reports",
        reason: "reason",
        decidedBy: "decided_by",
        decidedAt: "decided_at",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    reports: {
      name: "moderation_reports",
      app: {},
      optional: ["note", "resolvedBy", "resolvedAt"],
      typed: ["status"],
      lifecycle: { tenant: "tenant", user: "reporter", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        item: "item_id",
        reporter: "reporter_id",
        reason: "reason",
        note: "note",
        status: "status",
        resolvedBy: "resolved_by",
        resolvedAt: "resolved_at",
        createdAt: "created_at",
      },
    },
    actions: {
      name: "moderation_actions",
      app: {},
      typed: ["action", "fromStatus", "toStatus"],
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        item: "item_id",
        action: "action",
        fromStatus: "from_status",
        toStatus: "to_status",
        reason: "reason",
        actor: "actor_id",
        createdAt: "created_at",
      },
    },
    bans: {
      name: "moderation_bans",
      app: {},
      optional: ["reason", "bannedBy", "liftedBy"],
      lifecycle: { tenant: "tenant", user: "user", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        user: "user_id",
        reason: "reason",
        bannedBy: "banned_by",
        expiresAt: "expires_at",
        liftedBy: "lifted_by",
        liftedAt: "lifted_at",
        createdAt: "created_at",
      },
    },
  },
};

/** Where moderated content stands. `pending` waits for a first decision. */
const MODERATION_STATUSES = [
  "pending",
  "visible",
  "hidden",
  "removed",
] as const;

/** What a moderator or the module did to an item. */
const MODERATION_ACTIONS = [
  "submit",
  "approve",
  "hide",
  "remove",
  "restore",
  "ban",
  "auto_hide",
] as const;

const statusList = MODERATION_STATUSES.map((status) => sqlString(status)).join(
  ", ",
);

const actionList = MODERATION_ACTIONS.map((action) => sqlString(action)).join(
  ", ",
);

/**
 * The moderation tables, for this module and for the upgrades that move other
 * modules' moderation onto them.
 */
export function moderationTables(ctx: BlockSqlContext): string {
  if (!ctx.manages) {
    return "";
  }

  const items = ctx.table("items");
  const reports = ctx.table("reports");
  const actions = ctx.table("actions");
  const bans = ctx.table("bans");
  const i = (column: string): string => ctx.col("items", column);
  const r = (column: string): string => ctx.col("reports", column);
  const a = (column: string): string => ctx.col("actions", column);
  const b = (column: string): string => ctx.col("bans", column);

  const name = (logical: string, suffix: string): string =>
    sqlIdent(`${ctx.tableName(logical).name}_${suffix}`);

  const line = (
    logical: string,
    column: string,
    definition: (quoted: string) => string,
  ): string =>
    ctx.has(logical, column)
      ? `\n  ${ctx.col(logical, column)} ${definition(ctx.col(logical, column))},`
      : "";

  const subjectKey = ctx.owns("items")
    ? ""
    : `\ncreate unique index if not exists ${sqlIdent(`bsb_${ctx.tableName("items").name}_subject_key`)} on ${items} (${i("tenant")}, ${i("subjectType")}, ${i("subjectId")});`;

  return `create table if not exists ${items} (
  ${i("id")} uuid primary key default gen_random_uuid(),
  ${i("tenant")} ${ctx.idType} not null,
  ${i("subjectType")} text not null check (${i("subjectType")} ~ '^[a-z][a-z0-9_-]{0,62}$'),
  ${i("subjectId")} text not null check (length(${i("subjectId")}) between 1 and 200),
  ${i("author")} uuid references auth.users (id) on delete set null,
  ${i("status")} text not null default 'visible' check (${i("status")} in (${statusList})),
  ${i("openReports")} integer not null default 0 check (${i("openReports")} >= 0),
  ${i("reason")} text check (${i("reason")} is null or length(${i("reason")}) <= 1000),
  ${i("decidedBy")} uuid,
  ${i("decidedAt")} timestamptz,
  ${i("createdAt")} timestamptz not null default now(),
  ${i("updatedAt")} timestamptz not null default now(),
  unique (${i("tenant")}, ${i("subjectType")}, ${i("subjectId")})
);
create index if not exists ${name("items", "queue_idx")} on ${items} (${i("tenant")}, ${i("updatedAt")} desc) where ${i("status")} = 'pending' or ${i("openReports")} > 0;
create index if not exists ${name("items", "status_idx")} on ${items} (${i("tenant")}, ${i("status")}, ${i("updatedAt")} desc);
create index if not exists ${name("items", "author_idx")} on ${items} (${i("author")});${subjectKey}

create table if not exists ${reports} (
  ${r("id")} uuid primary key default gen_random_uuid(),
  ${r("tenant")} ${ctx.idType} not null,
  ${r("item")} uuid not null references ${items} (${i("id")}) on delete cascade,
  ${r("reporter")} uuid references auth.users (id) on delete cascade,
  ${r("reason")} text not null check (${r("reason")} ~ '^[a-z][a-z0-9_]{0,62}$'),${line("reports", "note", (note) => `text check (${note} is null or length(${note}) <= 1000)`)}
  ${r("status")} text not null default 'open' check (${r("status")} in ('open', 'resolved', 'dismissed')),${line("reports", "resolvedBy", () => "uuid")}${line("reports", "resolvedAt", () => "timestamptz")}
  ${r("createdAt")} timestamptz not null default now()
);
create unique index if not exists ${name("reports", "open_idx")} on ${reports} (${r("item")}, ${r("reporter")}) where ${r("status")} = 'open';
create index if not exists ${name("reports", "item_idx")} on ${reports} (${r("item")}, ${r("createdAt")} desc);
create index if not exists ${name("reports", "reporter_idx")} on ${reports} (${r("reporter")});

create table if not exists ${actions} (
  ${a("id")} uuid primary key default gen_random_uuid(),
  ${a("tenant")} ${ctx.idType} not null,
  ${a("item")} uuid not null references ${items} (${i("id")}) on delete cascade,
  ${a("action")} text not null check (${a("action")} in (${actionList})),
  ${a("fromStatus")} text,
  ${a("toStatus")} text not null,
  ${a("reason")} text,
  ${a("actor")} uuid,
  ${a("createdAt")} timestamptz not null default now()
);
create index if not exists ${name("actions", "item_idx")} on ${actions} (${a("item")}, ${a("createdAt")} desc);

create table if not exists ${bans} (
  ${b("id")} uuid primary key default gen_random_uuid(),
  ${b("tenant")} ${ctx.idType} not null,
  ${b("user")} uuid not null references auth.users (id) on delete cascade,${line("bans", "reason", (reason) => `text check (${reason} is null or length(${reason}) <= 1000)`)}${line("bans", "bannedBy", () => "uuid")}
  ${b("expiresAt")} timestamptz,${line("bans", "liftedBy", () => "uuid")}
  ${b("liftedAt")} timestamptz,
  ${b("createdAt")} timestamptz not null default now()
);
create unique index if not exists ${name("bans", "active_idx")} on ${bans} (${b("tenant")}, ${b("user")}) where ${b("liftedAt")} is null;
create index if not exists ${name("bans", "user_idx")} on ${bans} (${b("user")});
`;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const items = ctx.table("items");
  const reports = ctx.table("reports");
  const actions = ctx.table("actions");
  const bans = ctx.table("bans");
  const i = (column: string): string => ctx.col("items", column);
  const r = (column: string): string => ctx.col("reports", column);
  const a = (column: string): string => ctx.col("actions", column);
  const b = (column: string): string => ctx.col("bans", column);
  const read = ctx.permission("read", moduleOperations("moderation").read);

  const name = (logical: string, suffix: string): string =>
    sqlIdent(`${ctx.tableName(logical).name}_${suffix}`);

  const policies = ctx.manages
    ? `${lockTable(items, { read: true })}
drop policy if exists ${name("items", "read")} on ${items};
${renderPolicy(makePolicy({ table: items, name: name("items", "read"), command: "select", roles: ["authenticated"], using: ctx.scope.check(i("tenant"), read) }), { target: items })}
${lockTable(reports, { read: true })}
drop policy if exists ${name("reports", "read")} on ${reports};
${renderPolicy(makePolicy({ table: reports, name: name("reports", "read"), command: "select", roles: ["authenticated"], using: `${r("reporter")} = (select auth.uid()) or ${ctx.scope.check(r("tenant"), read)}` }), { target: reports })}
${lockTable(actions, { read: true })}
drop policy if exists ${name("actions", "read")} on ${actions};
${renderPolicy(makePolicy({ table: actions, name: name("actions", "read"), command: "select", roles: ["authenticated"], using: ctx.scope.check(a("tenant"), read) }), { target: actions })}
${lockTable(bans, { read: true })}
drop policy if exists ${name("bans", "read")} on ${bans};
${renderPolicy(makePolicy({ table: bans, name: name("bans", "read"), command: "select", roles: ["authenticated"], using: `${b("user")} = (select auth.uid()) or ${ctx.scope.check(b("tenant"), read)}` }), { target: bans })}
`
    : "";

  return `${schemaPreamble(ctx)}
${moderationTables(ctx)}
${policies}
${moderationFunctions(ctx)}`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "report_content",
      args: ["{id}", "text", "text", "text", "text"],
      returns: "jsonb",
    },
    { name: "moderate", args: ["uuid", "text", "text"], returns: "jsonb" },
    {
      name: "moderation_queue",
      args: ["{id}", "text", "text", "integer", "timestamptz"],
      returns: "jsonb",
    },
    {
      name: "moderation_statuses",
      args: ["{id}", "text", "text[]"],
      returns: "jsonb",
    },
    {
      name: "ban_user",
      args: ["{id}", "uuid", "text", "timestamptz"],
      returns: "jsonb",
    },
  ];
}

export const MODERATION: BlockSqlDefinition = {
  internal: ["moderation_track", "moderation_apply", "moderation_banned"],
  name: "moderation",
  scopes: ["tenant"],
  title: "Moderation",
  description:
    "Reports on any subject, a review queue, decisions (approve, hide, remove, restore, ban) with a log, user bans and an automatic hide threshold. Reviews moderate through it, and it hides and removes messages, comments included.",
  requires: ["memberships", "permissions"],
  integrates: ["messaging", "outbox", "audit"],
  target: "schema",
  modes: ["managed", "custom"],
  names: NAMES,
  contract,
  build,
};
