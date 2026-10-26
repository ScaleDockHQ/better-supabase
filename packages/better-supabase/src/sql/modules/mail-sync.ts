import type { MailSyncEvents } from "../../blocks/mail-sync/events.ts";
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
import { mailSyncFunctions } from "./mail-sync-functions.ts";
import { moduleOperations } from "./permissions-model.ts";

const ACCOUNT_PAYLOAD = [
  "organizationId",
  "accountId",
  "userId",
  "provider",
  "address",
] as const;

const MESSAGE_PAYLOAD = [
  "organizationId",
  "accountId",
  "userId",
  "threadId",
  "messageId",
  "direction",
  "fromAddress",
  "subjects",
] as const;

const TRACKING_PAYLOAD = [
  "organizationId",
  "accountId",
  "userId",
  "threadId",
  "messageId",
  "templateVersionId",
  "url",
  "subjects",
] as const;

const EVENTS: BlockSqlEvents<MailSyncEvents> = {
  "mail_account.connected": {
    subject: "mail-accounts",
    payload: [...ACCOUNT_PAYLOAD],
  },
  "mail_account.disconnected": {
    subject: "mail-accounts",
    payload: [...ACCOUNT_PAYLOAD],
  },
  "mail_message.received": {
    subject: "mail-messages",
    payload: [...MESSAGE_PAYLOAD],
    retries: true,
  },
  "mail_message.sent": {
    subject: "mail-messages",
    payload: [...MESSAGE_PAYLOAD],
    retries: true,
  },
  "mail_message.opened": {
    subject: "mail-messages",
    payload: [...TRACKING_PAYLOAD],
  },
  "mail_message.clicked": {
    subject: "mail-messages",
    payload: [...TRACKING_PAYLOAD],
  },
};

const NAMES: BlockSqlNames = {
  entities: {
    mail_thread: { table: "threads", singular: "mail_thread", primary: true },
    mail_account: { table: "accounts", singular: "mail_account" },
    mail_message: { table: "messages", singular: "mail_message" },
  },
  events: EVENTS,
  options: ["engagementType", "matchDomains"],
  tables: {
    accounts: {
      name: "mail_accounts",
      app: { writes: false },
      lifecycle: {
        tenant: "tenant",
        user: "user",
        credentials: ["credentialRef"],
        credentialSubject: "user",
      },
      columns: {
        id: "id",
        tenant: "tenant_id",
        user: "user_id",
        provider: "provider",
        address: "address",
        credentialRef: "credential_ref",
        share: "share",
        status: "status",
        cursor: "sync_cursor",
        lastSyncedAt: "last_synced_at",
        lastError: "last_error",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: ["lastError", "createdAt", "updatedAt"],
      typed: ["share", "status"],
    },
    threads: {
      name: "mail_threads",
      app: { writes: false },
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        account: "account_id",
        externalId: "external_id",
        subject: "subject",
        snippet: "snippet",
        lastMessageAt: "last_message_at",
        messageCount: "message_count",
        engagement: "engagement_id",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: [
        "subject",
        "snippet",
        "messageCount",
        "engagement",
        "createdAt",
        "updatedAt",
      ],
    },
    messages: {
      name: "mail_messages",
      app: { writes: false },
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        account: "account_id",
        thread: "thread_id",
        externalId: "external_id",
        rfcId: "rfc_message_id",
        direction: "direction",
        fromAddress: "from_address",
        fromName: "from_name",
        to: "to_addresses",
        cc: "cc_addresses",
        subject: "subject",
        snippet: "snippet",
        bodyText: "body_text",
        bodyHtml: "body_html",
        sentAt: "sent_at",
        templateVersion: "template_version_id",
        trackingHash: "tracking_hash",
        openedAt: "opened_at",
        openCount: "open_count",
        clickedAt: "clicked_at",
        clickCount: "click_count",
        createdAt: "created_at",
      },
      optional: [
        "rfcId",
        "fromName",
        "cc",
        "subject",
        "snippet",
        "bodyText",
        "bodyHtml",
        "templateVersion",
        "openCount",
        "clickCount",
        "createdAt",
      ],
      typed: ["direction"],
    },
    trackedLinks: {
      name: "mail_tracked_links",
      app: { writes: false },
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        tenant: "tenant_id",
        message: "message_id",
        position: "position",
        url: "url",
        clickCount: "click_count",
        createdAt: "created_at",
      },
      optional: ["createdAt"],
    },
    tracking: {
      name: "mail_tracking_events",
      app: { writes: false },
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        message: "message_id",
        kind: "kind",
        position: "position",
        userAgent: "user_agent",
        occurredAt: "occurred_at",
      },
      optional: ["position", "userAgent"],
      typed: ["kind"],
    },
    links: {
      name: "mail_thread_subjects",
      app: { writes: false },
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        tenant: "tenant_id",
        thread: "thread_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        source: "source",
        createdAt: "created_at",
      },
      optional: ["source", "createdAt"],
      typed: ["source"],
    },
  },
};

const TYPE = /^[a-z][a-z0-9_]{0,62}$/;

/** The names and keys the module's SQL shares between its files. */
export interface MailNames {
  readonly fn: (name: string) => string;
  readonly t: (table: string) => string;
  readonly a: (column: string) => string;
  readonly h: (column: string) => string;
  readonly m: (column: string) => string;
  readonly l: (column: string) => string;
  readonly k: (column: string) => string;
  readonly e: (column: string) => string;
  /** Whether the table has the column (an app's table may map it to null). */
  readonly has: (table: string, column: string) => boolean;
  /** A row as JSON, with the module's column names over an app's table. */
  readonly json: (table: string, alias: string) => string;
  /** The `order by` of a thread's subjects, `s` being the links alias. */
  readonly subjectOrder: string;
  readonly read: string;
  readonly connect: string;
  readonly send: string;
  readonly manage: string;
  readonly engagementType: string;
  readonly matchDomains: boolean;
}

function names(ctx: BlockSqlContext): MailNames {
  const keys = moduleOperations("mail-sync");
  const engagementType = ctx.text("engagementType", "email");

  if (!TYPE.test(engagementType)) {
    throw new TypeError(
      "blocks.mail-sync.options.engagementType must be a lowercase engagement type",
    );
  }

  const json = (table: string, alias: string): string => {
    if (ctx.owns(table)) {
      return `to_jsonb(${alias})`;
    }

    const columns = Object.entries(NAMES.tables[table]?.columns ?? {}).map(
      ([logical, name]) =>
        `${sqlString(name)}, ${ctx.has(table, logical) ? `${alias}.${ctx.col(table, logical)}` : "null"}`,
    );

    return `jsonb_build_object(${columns.join(", ")})`;
  };

  const link = (column: string): string => `s.${ctx.col("links", column)}`;

  return {
    fn: (name) => ctx.fn(name),
    t: (table) => ctx.table(table),
    a: (column) => ctx.col("accounts", column),
    h: (column) => ctx.col("threads", column),
    m: (column) => ctx.col("messages", column),
    l: (column) => ctx.col("links", column),
    k: (column) => ctx.col("trackedLinks", column),
    e: (column) => ctx.col("tracking", column),
    has: (table, column) => ctx.has(table, column),
    json,
    subjectOrder: [
      ...(ctx.has("links", "createdAt") ? [link("createdAt")] : []),
      link("subjectType"),
      link("subjectId"),
    ].join(", "),
    read: ctx.permission("read", keys.read),
    connect: ctx.permission("connect", keys.connect),
    send: ctx.permission("send", keys.send),
    manage: ctx.permission("manage", keys.manage),
    engagementType,
    matchDomains: ctx.flag("matchDomains", true),
  };
}

function tables(ctx: BlockSqlContext, n: MailNames): string {
  const { t, a, h, m, l, k, e } = n;

  const engagement = ctx.installed("activities")
    ? ` references ${ctx.of("activities").table("engagements")} (${ctx.of("activities").col("engagements", "id")}) on delete set null`
    : "";

  const visible = n.fn("mail_thread_visible");

  const policy = (table: string): string => `${ctx.tableName(table).name}_read`;

  const line = (
    table: string,
    column: string,
    sql: (name: string) => string,
  ): string =>
    ctx.has(table, column) ? `\n  ${sql(ctx.col(table, column))}` : "";

  const unique = (table: string, what: string, columns: string): string =>
    ctx.owns(table)
      ? ""
      : `\ncreate unique index if not exists ${sqlIdent(`bsb_${ctx.tableName(table).name}_${what}_key`)} on ${t(table)} (${columns});`;

  return `create table if not exists ${t("accounts")} (
  ${a("id")} uuid primary key default gen_random_uuid(),
  ${a("tenant")} ${ctx.idType} not null,
  ${a("user")} uuid not null references auth.users (id) on delete cascade,
  ${a("provider")} text not null check (${a("provider")} ~ '^[a-z][a-z0-9-]{0,39}$'),
  ${a("address")} text not null check (${a("address")} = lower(${a("address")}) and ${a("address")} ~ '^[^@[:space:]]+@[^@[:space:]]+$'),
  ${a("credentialRef")} jsonb not null check (jsonb_typeof(${a("credentialRef")}) = 'object'),
  ${a("share")} text not null default 'records' check (${a("share")} in ('records', 'private')),
  ${a("status")} text not null default 'active' check (${a("status")} in ('active', 'paused', 'error', 'disconnected')),
  ${a("cursor")} text,
  ${a("lastSyncedAt")} timestamptz,${line("accounts", "lastError", (c) => `${c} text,`)}${line("accounts", "createdAt", (c) => `${c} timestamptz not null default now(),`)}${line("accounts", "updatedAt", (c) => `${c} timestamptz not null default now(),`)}
  unique (${a("tenant")}, ${a("user")}, ${a("address")})
);${unique("accounts", "address", `${a("tenant")}, ${a("user")}, ${a("address")}`)}
create index if not exists ${ctx.naming.rename("mail_accounts_user_idx")} on ${t("accounts")} (${a("user")});
create index if not exists ${ctx.naming.rename("mail_accounts_due_idx")} on ${t("accounts")} (${a("lastSyncedAt")} nulls first) where ${a("status")} = 'active';
${lockTable(t("accounts"), { read: true })}
create table if not exists ${t("threads")} (
  ${h("id")} uuid primary key default gen_random_uuid(),
  ${h("tenant")} ${ctx.idType} not null,
  ${h("account")} uuid not null references ${t("accounts")} (${a("id")}) on delete cascade,
  ${h("externalId")} text not null,${line("threads", "subject", (c) => `${c} text,`)}${line("threads", "snippet", (c) => `${c} text,`)}
  ${h("lastMessageAt")} timestamptz,${line("threads", "messageCount", (c) => `${c} integer not null default 0,`)}${line("threads", "engagement", (c) => `${c} uuid${engagement},`)}${line("threads", "createdAt", (c) => `${c} timestamptz not null default now(),`)}${line("threads", "updatedAt", (c) => `${c} timestamptz not null default now(),`)}
  unique (${h("account")}, ${h("externalId")})
);${unique("threads", "external", `${h("account")}, ${h("externalId")}`)}
create index if not exists ${ctx.naming.rename("mail_threads_tenant_recent_idx")} on ${t("threads")} (${h("tenant")}, ${h("lastMessageAt")} desc);
${ctx.has("threads", "engagement") ? `create index if not exists ${ctx.naming.rename("mail_threads_engagement_idx")} on ${t("threads")} (${h("engagement")}) where ${h("engagement")} is not null;\n` : ""}${lockTable(t("threads"), { read: true })}
create table if not exists ${t("messages")} (
  ${m("id")} uuid primary key default gen_random_uuid(),
  ${m("tenant")} ${ctx.idType} not null,
  ${m("account")} uuid not null references ${t("accounts")} (${a("id")}) on delete cascade,
  ${m("thread")} uuid not null references ${t("threads")} (${h("id")}) on delete cascade,
  ${m("externalId")} text not null,${line("messages", "rfcId", (c) => `${c} text,`)}
  ${m("direction")} text not null check (${m("direction")} in ('inbound', 'outbound')),
  ${m("fromAddress")} text,${line("messages", "fromName", (c) => `${c} text,`)}
  ${m("to")} text[] not null default '{}',${line("messages", "cc", (c) => `${c} text[] not null default '{}',`)}${line("messages", "subject", (c) => `${c} text,`)}${line("messages", "snippet", (c) => `${c} text,`)}${line("messages", "bodyText", (c) => `${c} text,`)}${line("messages", "bodyHtml", (c) => `${c} text,`)}
  ${m("sentAt")} timestamptz not null,${line("messages", "templateVersion", (c) => `${c} uuid,`)}
  ${m("trackingHash")} text check (${m("trackingHash")} ~ '^[0-9a-f]{64}$'),
  ${m("openedAt")} timestamptz,${line("messages", "openCount", (c) => `${c} integer not null default 0,`)}
  ${m("clickedAt")} timestamptz,${line("messages", "clickCount", (c) => `${c} integer not null default 0,`)}${line("messages", "createdAt", (c) => `${c} timestamptz not null default now(),`)}
  unique (${m("account")}, ${m("externalId")})
);
create index if not exists ${ctx.naming.rename("mail_messages_thread_idx")} on ${t("messages")} (${m("thread")}, ${m("sentAt")});
${ctx.has("messages", "rfcId") ? `create index if not exists ${ctx.naming.rename("mail_messages_rfc_idx")} on ${t("messages")} (${m("account")}, ${m("rfcId")}) where ${m("rfcId")} is not null;\n` : ""}create unique index if not exists ${ctx.naming.rename("mail_messages_tracking_idx")} on ${t("messages")} (${m("trackingHash")}) where ${m("trackingHash")} is not null;
${ctx.has("messages", "templateVersion") ? `create index if not exists ${ctx.naming.rename("mail_messages_template_idx")} on ${t("messages")} (${m("tenant")}, ${m("templateVersion")}) where ${m("templateVersion")} is not null;\n` : ""}${lockTable(t("messages"), { read: true })}
create table if not exists ${t("trackedLinks")} (
  ${k("tenant")} ${ctx.idType} not null,
  ${k("message")} uuid not null references ${t("messages")} (${m("id")}) on delete cascade,
  ${k("position")} integer not null check (${k("position")} >= 0),
  ${k("url")} text not null check (${k("url")} ~* '^https?://' and length(${k("url")}) <= 2048),
  ${k("clickCount")} integer not null default 0,${line("trackedLinks", "createdAt", (c) => `${c} timestamptz not null default now(),`)}
  primary key (${k("message")}, ${k("position")})
);
${lockTable(t("trackedLinks"), { read: true })}
create table if not exists ${t("tracking")} (
  ${e("id")} uuid primary key default gen_random_uuid(),
  ${e("tenant")} ${ctx.idType} not null,
  ${e("message")} uuid not null references ${t("messages")} (${m("id")}) on delete cascade,
  ${e("kind")} text not null check (${e("kind")} in ('open', 'click')),${line("tracking", "position", (c) => `${c} integer,`)}${line("tracking", "userAgent", (c) => `${c} text check (length(${c}) <= 300),`)}
  ${e("occurredAt")} timestamptz not null default now()
);
create index if not exists ${ctx.naming.rename("mail_tracking_events_message_idx")} on ${t("tracking")} (${e("message")}, ${e("occurredAt")});
${lockTable(t("tracking"), { read: true })}
create table if not exists ${t("links")} (
  ${l("tenant")} ${ctx.idType} not null,
  ${l("thread")} uuid not null references ${t("threads")} (${h("id")}) on delete cascade,
  ${l("subjectType")} text not null,
  ${l("subjectId")} text not null,${line("links", "source", (c) => `${c} text not null default 'match' check (${c} in ('match', 'manual')),`)}${line("links", "createdAt", (c) => `${c} timestamptz not null default now(),`)}
  primary key (${l("thread")}, ${l("subjectType")}, ${l("subjectId")})
);${unique("links", "subject", `${l("thread")}, ${l("subjectType")}, ${l("subjectId")}`)}
create index if not exists ${ctx.naming.rename("mail_thread_subjects_subject_idx")} on ${t("links")} (${l("subjectType")}, ${l("subjectId")});
${lockTable(t("links"), { read: true })}

-- Whether the caller may read a thread: its mailbox is theirs, or the mailbox
-- shares with records and the caller can read one of the thread's records.
create or replace function ${visible}(thread uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from ${t("threads")} x
    join ${t("accounts")} k on k.${a("id")} = x.${h("account")}
    where x.${h("id")} = $1
      and (k.${a("user")} = auth.uid() or (
        k.${a("share")} = 'records'
        and ${ctx.scope.can(`x.${h("tenant")}`, n.read)}
        and exists (
          select 1 from ${t("links")} s
          where s.${l("thread")} = x.${h("id")}
            and ${ctx.of("subjects").fn("can_subject")}(s.${l("subjectType")}, s.${l("subjectId")}, 'read')
        )
      ))
  )
$$;
revoke execute on function ${visible}(uuid) from public, anon;
grant execute on function ${visible}(uuid) to authenticated, service_role;

${renderPolicy(makePolicy({ table: t("accounts"), name: policy("accounts"), command: "select", roles: ["authenticated"], using: `${a("user")} = (select auth.uid()) or ${ctx.scope.check(a("tenant"), n.manage)}` }), { drop: true, target: t("accounts") })}
${renderPolicy(makePolicy({ table: t("threads"), name: policy("threads"), command: "select", roles: ["authenticated"], using: `${visible}(${h("id")})` }), { drop: true, target: t("threads") })}
${renderPolicy(makePolicy({ table: t("messages"), name: policy("messages"), command: "select", roles: ["authenticated"], using: `${visible}(${m("thread")})` }), { drop: true, target: t("messages") })}
${renderPolicy(makePolicy({ table: t("links"), name: policy("links"), command: "select", roles: ["authenticated"], using: `${visible}(${l("thread")})` }), { drop: true, target: t("links") })}
${renderPolicy(makePolicy({ table: t("trackedLinks"), name: policy("trackedLinks"), command: "select", roles: ["authenticated"], using: `exists (select 1 from ${t("messages")} y where y.${m("id")} = ${k("message")} and ${visible}(y.${m("thread")}))` }), { drop: true, target: t("trackedLinks") })}
${renderPolicy(makePolicy({ table: t("tracking"), name: policy("tracking"), command: "select", roles: ["authenticated"], using: `exists (select 1 from ${t("messages")} y where y.${m("id")} = ${e("message")} and ${visible}(y.${m("thread")}))` }), { drop: true, target: t("tracking") })}
`;
}

function build(ctx: BlockSqlContext): string {
  const n = names(ctx);

  return `${schemaPreamble(ctx)}
-- Gmail, Outlook and other mailboxes synced per member: threads and messages
-- linked to the people and companies they involve, logged as engagements.
${tables(ctx, n)}${mailSyncFunctions(ctx, n)}`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "connect_mail_account",
      args: ["{id}", "text", "text", "jsonb", "text"],
      returns: "jsonb",
    },
    {
      name: "update_mail_account",
      args: ["uuid", "text", "boolean"],
      returns: "jsonb",
    },
    {
      name: "disconnect_mail_account",
      args: ["uuid", "boolean"],
      returns: "boolean",
    },
    { name: "mail_accounts_of", args: ["{id}"], returns: "jsonb" },
    { name: "get_mail_account", args: ["uuid"], returns: "jsonb" },
    {
      name: "due_mail_accounts",
      args: ["integer", "interval"],
      returns: "jsonb",
    },
    { name: "ingest_mail", args: ["uuid", "jsonb", "text"], returns: "jsonb" },
    {
      name: "set_mail_account_status",
      args: ["uuid", "text", "text"],
      returns: "boolean",
    },
    { name: "record_sent_mail", args: ["uuid", "jsonb"], returns: "jsonb" },
    { name: "link_mail_thread", args: ["uuid", "jsonb"], returns: "jsonb" },
    {
      name: "unlink_mail_thread",
      args: ["uuid", "text", "text"],
      returns: "boolean",
    },
    {
      name: "mail_threads_of",
      args: ["text", "text", "timestamptz", "integer"],
      returns: "jsonb",
    },
    {
      name: "list_mail_threads",
      args: ["{id}", "uuid", "timestamptz", "integer"],
      returns: "jsonb",
    },
    { name: "get_mail_thread", args: ["uuid"], returns: "jsonb" },
    {
      name: "track_mail",
      args: ["text", "text", "integer", "text"],
      returns: "jsonb",
    },
    {
      name: "mail_template_stats",
      args: ["{id}", "timestamptz"],
      returns: "jsonb",
    },
  ];
}

export const MAIL_SYNC: BlockSqlDefinition = {
  name: "mail-sync",
  scopes: ["tenant"],
  title: "Mail sync",
  description:
    "Gmail, Outlook and other mailboxes synced per member through their own OAuth grant: threads and messages linked to the people and companies they involve, logged as email engagements, and a record of the mail members send, with opens and clicks per message and per template version.",
  requires: ["memberships", "permissions", "subjects"],
  integrates: ["outbox", "audit", "contacts", "activities", "data-lifecycle"],
  target: "schema",
  modes: ["managed"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
